/**
 * Arma y envía el expediente de cierre de una propiedad a Org B.
 * La autenticación la resuelve la Named Credential OrgB_Cierre
 * (OAuth 2.0 Client Credentials): el código nunca ve ningún secreto.
 *
 * Nota de diseño: la clase es "with sharing", por lo que respeta la
 * visibilidad de registros del usuario. La lectura no usa USER_MODE a
 * propósito: es un proceso de sistema que debe enviar el expediente
 * completo aunque el usuario que acepta la oferta no tenga permiso de
 * campo sobre el nombre del comprador.
 */
public with sharing class CierreVentaCliente {
  public class CierreException extends Exception {
  }

  // Contrato JSON con Org B. Si cambia un nombre, debe cambiar en
  // el endpoint de Org B.
  public class CierrePayload {
    public String idPropiedadOrigen;
    public String nombrePropiedad;
    public Decimal montoFinal;
    public String compradorNombre;
  }

  public static CierrePayload armarPayload(Id propiedadId) {
    List<Propiedad__c> propiedades = [
      SELECT Id, Name
      FROM Propiedad__c
      WHERE Id = :propiedadId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (propiedades.isEmpty()) {
      throw new CierreException(
        'La propiedad no existe o no hay acceso a ella.'
      );
    }

    // Si hubiera varias ofertas aceptadas, se toma la de mayor monto.
    List<Oferta__c> ofertas = [
      SELECT Id, Monto_de_la_Oferta__c, Comprador__r.Name
      FROM Oferta__c
      WHERE Propiedad__c = :propiedadId AND Estado__c = 'Aceptada'
      WITH SYSTEM_MODE
      ORDER BY Monto_de_la_Oferta__c DESC
      LIMIT 1
    ];
    if (ofertas.isEmpty()) {
      throw new CierreException('La propiedad no tiene una oferta aceptada.');
    }

    CierrePayload payload = new CierrePayload();
    payload.idPropiedadOrigen = propiedades[0].Id;
    payload.nombrePropiedad = propiedades[0].Name;
    payload.montoFinal = ofertas[0].Monto_de_la_Oferta__c;
    payload.compradorNombre = ofertas[0].Comprador__r?.Name;
    return payload;
  }

  public static HttpResponse enviar(CierrePayload payload) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:OrgB_Cierre/services/apexrest/cierre/v1/');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setTimeout(20000);
    req.setBody(JSON.serialize(payload));
    return new Http().send(req);
  }
}
