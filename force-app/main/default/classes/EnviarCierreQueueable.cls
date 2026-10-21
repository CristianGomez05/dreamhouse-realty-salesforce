/**
 * Envía el cierre a Org B fuera de la transacción del Flow.
 * Se usa Queueable porque un callout no puede ejecutarse en la misma
 * transacción que un DML sin confirmar (el Flow acaba de actualizar la
 * propiedad). Reintenta hasta MAX_INTENTOS veces, con un minuto de
 * espera entre intentos, y después deja el estado en Error.
 */
public with sharing class EnviarCierreQueueable implements Queueable, Database.AllowsCallouts {
  @TestVisible
  private static final Integer MAX_INTENTOS = 3;

  private final Id propiedadId;
  private final Integer intento;

  public EnviarCierreQueueable(Id propiedadId, Integer intento) {
    this.propiedadId = propiedadId;
    this.intento = intento;
  }

  public void execute(QueueableContext contexto) {
    String error;
    try {
      CierreVentaCliente.CierrePayload payload = CierreVentaCliente.armarPayload(
        propiedadId
      );
      HttpResponse respuesta = CierreVentaCliente.enviar(payload);
      if (respuesta.getStatusCode() >= 200 && respuesta.getStatusCode() < 300) {
        registrarResultado('Enviado', null);
        return;
      }
      error = 'HTTP ' + respuesta.getStatusCode() + ': ' + respuesta.getBody();
    } catch (Exception e) {
      error = e.getMessage();
    }

    // Se antepone el número de intento para poder verificar, desde el
    // propio registro, cuántos intentos se hicieron realmente.
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
      intento < MAX_INTENTOS && !System.AsyncInfo.hasMaxStackDepth();
    if (puedeReintentar) {
      registrarMensaje(detalle);
      System.enqueueJob(new EnviarCierreQueueable(propiedadId, intento + 1), 1);
    } else {
      registrarResultado('Error', detalle);
    }
  }

  // Estos dos campos son de control de la integración, no datos del
  // usuario: se escriben en modo sistema para que el resultado quede
  // registrado aunque el usuario no tenga permiso de edición sobre ellos.
  private void registrarResultado(String estado, String mensaje) {
    Propiedad__c propiedad = new Propiedad__c(
      Id = propiedadId,
      Estado_de_Cierre_Legal__c = estado,
      Ultimo_Error_Integracion__c = mensaje?.left(1000)
    );
    Database.update(propiedad, AccessLevel.SYSTEM_MODE);
  }

  // Solo deja constancia del último fallo; el estado no cambia hasta
  // que el envío tenga éxito o se agoten los intentos.
  private void registrarMensaje(String mensaje) {
    Propiedad__c propiedad = new Propiedad__c(
      Id = propiedadId,
      Ultimo_Error_Integracion__c = mensaje.left(1000)
    );
    Database.update(propiedad, AccessLevel.SYSTEM_MODE);
  }
}
