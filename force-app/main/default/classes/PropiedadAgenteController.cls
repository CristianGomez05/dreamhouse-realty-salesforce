/**
 * Controlador del Panel del Agente de DreamHouse Realty.
 * Expone las propiedades asignadas al usuario en sesión con sus visitas
 * próximas y permite cerrar visitas, respetando el modelo de seguridad
 * existente (OWD Private + Sharing Rules por Región).
 *
 * Nota de diseño: "with sharing" aplica las Sharing Rules (qué registros
 * puede ver el usuario), pero no filtra por "mis propios registros".
 * Ese filtro es lógica de negocio y se declara de forma explícita en
 * el WHERE, porque la Sharing Rule es por Región, no por agente.
 */
public with sharing class PropiedadAgenteController {
  @AuraEnabled(cacheable=true)
  public static List<Propiedad__c> getPropiedadesDelAgente(
    String terminoBusqueda
  ) {
    // Normaliza el término de búsqueda para el LIKE. Si llega vacío
    // o nulo, se devuelven todas las propiedades del agente.
    String termino = String.isBlank(terminoBusqueda)
      ? ''
      : terminoBusqueda.trim();
    String terminoLike = '%' + termino + '%';

    return [
      SELECT
        Id,
        Name,
        Estado__c,
        Region__c,
        Precio_de_Lista__c,
        Oferta_Mas_Alta__c,
        Total_de_Ofertas__c,
        Estado_de_Cierre_Legal__c,
        (
          SELECT Id, Fecha_de_Visita__c, Notas__c, Realizada__c
          FROM Visitas__r
          WHERE Fecha_de_Visita__c >= TODAY AND Realizada__c = FALSE
          ORDER BY Fecha_de_Visita__c ASC
        )
      FROM Propiedad__c
      WHERE
        Agente_Asignado__c = :UserInfo.getUserId()
        AND (Name LIKE :terminoLike
        OR Region__c LIKE :terminoLike)
      WITH USER_MODE
      ORDER BY Name ASC
      LIMIT 200
    ];
  }

  @AuraEnabled
  public static void marcarVisitaRealizada(Id visitaId) {
    if (visitaId == null) {
      throw crearExcepcion('Se requiere el identificador de la visita.');
    }

    // La lectura se realiza en modo usuario: si el usuario no tiene
    // acceso al registro, la consulta no lo devuelve.
    List<Visita__c> visitas = [
      SELECT Id, Agente_Asignado__c, Realizada__c
      FROM Visita__c
      WHERE Id = :visitaId
      WITH USER_MODE
      LIMIT 1
    ];

    if (visitas.isEmpty()) {
      throw crearExcepcion('La visita no existe o no hay acceso a ella.');
    }

    Visita__c visita = visitas[0];

    // Autorización explícita de negocio: solo el agente asignado
    // puede cerrar la visita desde el panel.
    if (visita.Agente_Asignado__c != UserInfo.getUserId()) {
      throw crearExcepcion(
        'Solo el agente asignado puede marcar la visita como realizada.'
      );
    }

    // Operación idempotente: una visita ya cerrada no se vuelve
    // a procesar.
    if (visita.Realizada__c) {
      return;
    }

    // La actualización se ejecuta en modo usuario: respeta el acceso
    // a nivel de registro, el FLS y las reglas de validación.
    Visita__c cierre = new Visita__c(Id = visita.Id, Realizada__c = true);
    try {
      update as user cierre;
    } catch (DmlException e) {
      throw crearExcepcion(e.getDmlMessage(0));
    }
  }

  // AuraHandledException requiere setMessage para que el texto
  // llegue al cliente; sin él, el mensaje se reemplaza por
  // "Script-thrown exception".
  private static AuraHandledException crearExcepcion(String mensaje) {
    AuraHandledException ex = new AuraHandledException(mensaje);
    ex.setMessage(mensaje);
    return ex;
  }
}
