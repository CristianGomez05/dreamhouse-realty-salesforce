/**
 * Notifica a Org A que legal aprobó el cierre, fuera de la transacción del
 * Flow. Reintenta hasta MAX_INTENTOS veces, con un minuto de espera entre
 * intentos, y después deja el estado en Error. El resultado queda en el
 * propio Cierre__c, con el número de intento en el mensaje.
 */
public with sharing class NotificarCierreQueueable implements Queueable, Database.AllowsCallouts {
  @TestVisible
  private static final Integer MAX_INTENTOS = 3;

  // Interruptor para pruebas: Apex no permite encadenar un Queueable
  // dentro de un test. En producción siempre es true.
  @TestVisible
  private static Boolean encolarReintentos = true;

  private final Id cierreId;
  private final Integer intento;

  public NotificarCierreQueueable(Id cierreId, Integer intento) {
    this.cierreId = cierreId;
    this.intento = intento;
  }

  public void execute(QueueableContext contexto) {
    String error;
    try {
      Cierre__c cierre = CierreOrigenCliente.cargarCierre(cierreId);
      CierreOrigenCliente.ResultadoPayload payload = CierreOrigenCliente.armarPayload(
        cierre
      );
      HttpResponse respuesta = CierreOrigenCliente.notificar(payload);
      if (respuesta.getStatusCode() >= 200 && respuesta.getStatusCode() < 300) {
        registrarResultado('Notificada', null);
        return;
      }
      error = 'HTTP ' + respuesta.getStatusCode() + ': ' + respuesta.getBody();
    } catch (Exception e) {
      error = e.getMessage();
    }

    String detalle =
      'Intento ' +
      intento +
      ' de ' +
      MAX_INTENTOS +
      ' - ' +
      error;

    // Si la plataforma no permite encadenar otro job (por ejemplo, dentro
    // de una prueba Apex), el intento actual se trata como el último.
    Boolean puedeReintentar =
      intento < MAX_INTENTOS && !profundidadMaximaAlcanzada();
    if (puedeReintentar) {
      registrarMensaje(detalle);
      if (encolarReintentos) {
        System.enqueueJob(
          new NotificarCierreQueueable(cierreId, intento + 1),
          1
        );
      }
    } else {
      registrarResultado('Error', detalle);
    }
  }

  // hasMaxStackDepth() solo puede llamarse dentro de un Queueable o un
  // Finalizer. Fuera de ese contexto (p. ej. una prueba que invoca
  // execute directamente) lanza AsyncException: allí no hay cadena que
  // proteger, así que se considera que no se alcanzó el límite.
  private static Boolean profundidadMaximaAlcanzada() {
    try {
      return System.AsyncInfo.hasMaxStackDepth();
    } catch (System.AsyncException e) {
      return false;
    }
  }

  // Campos de control de la integración: se escriben en modo sistema para
  // que el resultado quede registrado sin depender de los permisos del usuario.
  private void registrarResultado(String estado, String mensaje) {
    Cierre__c cierre = new Cierre__c(
      Id = cierreId,
      Notificacion_a_Origen__c = estado,
      Ultimo_Error_Integracion__c = mensaje?.left(1000)
    );
    Database.update(cierre, AccessLevel.SYSTEM_MODE);
  }

  private void registrarMensaje(String mensaje) {
    Cierre__c cierre = new Cierre__c(
      Id = cierreId,
      Ultimo_Error_Integracion__c = mensaje.left(1000)
    );
    Database.update(cierre, AccessLevel.SYSTEM_MODE);
  }
}
