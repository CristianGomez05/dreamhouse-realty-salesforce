/**
 * Endpoint de Org B que recibe el expediente de cierre enviado desde Org A.
 * URL: /services/apexrest/cierre/v1/
 *
 * Es idempotente: Id_Propiedad_Origen__c es un External ID único, de modo
 * que un reenvío (por ejemplo, un reintento de Org A) no duplica el cierre.
 * Una vez que legal decidió (Aprobado o Rechazado), un reenvío no
 * modifica el registro.
 *
 * Se ejecuta como el usuario de integración de la External Client App y
 * usa modo usuario: solo puede hacer lo que su permission set permite.
 */
@RestResource(urlMapping='/cierre/v1/*')
global with sharing class CierreRestService {
  // Contrato JSON con Org A (ver CierreVentaCliente.CierrePayload).
  private class CierrePayload {
    public String idPropiedadOrigen;
    public String nombrePropiedad;
    public Decimal montoFinal;
    public String compradorNombre;
  }

  private class SolicitudInvalidaException extends Exception {
  }

  @HttpPost
  global static void doPost() {
    try {
      CierrePayload payload = leerPayload(RestContext.request);

      List<Cierre__c> existentes = [
        SELECT Id, Estado_Legal__c
        FROM Cierre__c
        WHERE Id_Propiedad_Origen__c = :payload.idPropiedadOrigen
        WITH USER_MODE
        LIMIT 1
      ];

      if (existentes.isEmpty()) {
        Cierre__c nuevo = new Cierre__c(
          Id_Propiedad_Origen__c = payload.idPropiedadOrigen,
          Estado_Legal__c = 'Recibido'
        );
        copiarDatos(payload, nuevo);
        insert as user nuevo;
        responder(201, nuevo.Id, 'Recibido', true);
        return;
      }

      Cierre__c actual = existentes[0];
      if (
        actual.Estado_Legal__c == 'Recibido' ||
        actual.Estado_Legal__c == 'En Revisión'
      ) {
        copiarDatos(payload, actual);
        update as user actual;
      }
      responder(200, actual.Id, actual.Estado_Legal__c, false);
    } catch (SolicitudInvalidaException e) {
      responderError(400, e.getMessage());
    } catch (Exception e) {
      responderError(500, e.getMessage());
    }
  }

  private static CierrePayload leerPayload(RestRequest solicitud) {
    String cuerpo = solicitud.requestBody?.toString();
    if (String.isBlank(cuerpo)) {
      throw new SolicitudInvalidaException(
        'El cuerpo de la solicitud está vacío.'
      );
    }

    CierrePayload payload;
    try {
      payload = (CierrePayload) JSON.deserialize(cuerpo, CierrePayload.class);
    } catch (JSONException e) {
      throw new SolicitudInvalidaException(
        'El JSON no es válido: ' + e.getMessage()
      );
    }

    if (
      payload == null ||
      String.isBlank(payload.idPropiedadOrigen) ||
      (payload.idPropiedadOrigen.length() != 15 &&
      payload.idPropiedadOrigen.length() != 18)
    ) {
      throw new SolicitudInvalidaException(
        'idPropiedadOrigen debe ser un Id de Salesforce de 15 o 18 caracteres.'
      );
    }
    if (payload.montoFinal == null || payload.montoFinal <= 0) {
      throw new SolicitudInvalidaException(
        'montoFinal debe ser mayor que cero.'
      );
    }
    return payload;
  }

  private static void copiarDatos(CierrePayload payload, Cierre__c cierre) {
    cierre.Nombre_Propiedad__c = payload.nombrePropiedad?.left(80);
    cierre.Monto_Final__c = payload.montoFinal;
    cierre.Comprador_Nombre__c = payload.compradorNombre?.left(80);
  }

  private static void responder(
    Integer codigo,
    Id cierreId,
    String estadoLegal,
    Boolean creado
  ) {
    escribir(
      codigo,
      new Map<String, Object>{
        'idCierre' => cierreId,
        'estadoLegal' => estadoLegal,
        'creado' => creado
      }
    );
  }

  private static void responderError(Integer codigo, String mensaje) {
    escribir(codigo, new Map<String, Object>{ 'error' => mensaje });
  }

  private static void escribir(Integer codigo, Map<String, Object> cuerpo) {
    RestResponse respuesta = RestContext.response;
    respuesta.statusCode = codigo;
    respuesta.addHeader('Content-Type', 'application/json');
    respuesta.responseBody = Blob.valueOf(JSON.serialize(cuerpo));
  }
}
