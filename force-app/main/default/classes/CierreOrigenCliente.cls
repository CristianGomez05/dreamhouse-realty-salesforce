/**
 * Arma y envía a Org A el resultado del cierre legal.
 * La autenticación la resuelve la Named Credential OrgA_Cierre
 * (OAuth 2.0 Client Credentials): el código nunca ve ningún secreto.
 *
 * La lectura es en modo sistema a propósito: es un proceso de sistema que
 * debe poder leer el cierre sin importar los permisos de campo del usuario
 * que lo aprobó.
 */
public with sharing class CierreOrigenCliente {
  public class CierreException extends Exception {
  }

  // Contrato JSON con Org A (ver CierreEntranteRest.ResultadoPayload).
  public class ResultadoPayload {
    public String idPropiedadOrigen;
    public String estadoLegal;
  }

  public static Cierre__c cargarCierre(Id cierreId) {
    List<Cierre__c> cierres = [
      SELECT Id, Id_Propiedad_Origen__c, Estado_Legal__c
      FROM Cierre__c
      WHERE Id = :cierreId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (cierres.isEmpty()) {
      throw new CierreException('El cierre no existe.');
    }
    return cierres[0];
  }

  public static ResultadoPayload armarPayload(Cierre__c cierre) {
    if (
      cierre.Estado_Legal__c != 'Aprobado' &&
      cierre.Estado_Legal__c != 'Rechazado'
    ) {
      throw new CierreException(
        'Solo se notifica un cierre en estado Aprobado o Rechazado.'
      );
    }
    if (String.isBlank(cierre.Id_Propiedad_Origen__c)) {
      throw new CierreException(
        'El cierre no tiene Id de propiedad de origen.'
      );
    }

    ResultadoPayload payload = new ResultadoPayload();
    payload.idPropiedadOrigen = cierre.Id_Propiedad_Origen__c;
    payload.estadoLegal = cierre.Estado_Legal__c;
    return payload;
  }

  public static HttpResponse notificar(ResultadoPayload payload) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:OrgA_Cierre/services/apexrest/cierre/v1/');
    req.setMethod('PATCH');
    req.setHeader('Content-Type', 'application/json');
    req.setTimeout(20000);
    req.setBody(JSON.serialize(payload));
    return new Http().send(req);
  }
}
