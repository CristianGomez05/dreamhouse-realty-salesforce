/**
 * Endpoint de Org A que recibe de Org B el resultado del cierre legal.
 * URL: /services/apexrest/cierre/v1/
 *
 * Transiciones permitidas, siempre sobre una propiedad en Bajo Contrato:
 *  - Aprobado: Bajo Contrato -> Cerrada (y estado de cierre = Cerrado).
 *  - Rechazado: la propiedad sigue en Bajo Contrato y el estado de cierre
 *    pasa a Rechazado. Qué hacer después lo decide el agente.
 * Cualquier otra combinación se rechaza con 400, de modo que ni un error
 * ni una llamada indebida puedan mover una propiedad a un estado que el
 * negocio no autoriza.
 *
 * No modifica Oferta__c, para no interferir con el Approval Process.
 * Es idempotente: repetir el mismo resultado responde 200 sin cambios.
 * Se ejecuta como el usuario de integración y usa modo usuario.
 */
@RestResource(urlMapping='/cierre/v1/*')
global with sharing class CierreEntranteRest {
  // Contrato JSON con Org B.
  private class ResultadoPayload {
    public String idPropiedadOrigen;
    public String estadoLegal;
  }

  private class SolicitudInvalidaException extends Exception {
  }

  @HttpPatch
  global static void doPatch() {
    try {
      ResultadoPayload payload = leerPayload(RestContext.request);
      Id propiedadId = leerId(payload.idPropiedadOrigen);

      List<Propiedad__c> propiedades = [
        SELECT Id, Estado__c, Estado_de_Cierre_Legal__c
        FROM Propiedad__c
        WHERE Id = :propiedadId
        WITH USER_MODE
        LIMIT 1
      ];
      if (propiedades.isEmpty()) {
        escribir(
          404,
          new Map<String, Object>{
            'error' => 'La propiedad no existe o no hay acceso a ella.'
          }
        );
        return;
      }

      if (payload.estadoLegal == 'Aprobado') {
        aprobar(propiedades[0]);
      } else {
        rechazar(propiedades[0]);
      }
    } catch (SolicitudInvalidaException e) {
      escribir(400, new Map<String, Object>{ 'error' => e.getMessage() });
    } catch (Exception e) {
      escribir(500, new Map<String, Object>{ 'error' => e.getMessage() });
    }
  }

  private static void aprobar(Propiedad__c propiedad) {
    if (propiedad.Estado__c == 'Cerrada') {
      responder(200, propiedad.Id, 'Cerrada', false);
      return;
    }
    if (propiedad.Estado__c != 'Bajo Contrato') {
      throw new SolicitudInvalidaException(
        'Solo se puede cerrar una propiedad en Bajo Contrato. Estado actual: ' +
        propiedad.Estado__c
      );
    }

    propiedad.Estado__c = 'Cerrada';
    propiedad.Estado_de_Cierre_Legal__c = 'Cerrado';
    propiedad.Ultimo_Error_Integracion__c = null;
    update as user propiedad;
    responder(200, propiedad.Id, 'Cerrada', true);
  }

  private static void rechazar(Propiedad__c propiedad) {
    if (propiedad.Estado__c == 'Cerrada') {
      throw new SolicitudInvalidaException(
        'No se puede rechazar el cierre de una propiedad ya cerrada.'
      );
    }
    if (propiedad.Estado__c != 'Bajo Contrato') {
      throw new SolicitudInvalidaException(
        'Solo se puede rechazar el cierre de una propiedad en Bajo Contrato. Estado actual: ' +
        propiedad.Estado__c
      );
    }
    if (propiedad.Estado_de_Cierre_Legal__c == 'Rechazado') {
      responder(200, propiedad.Id, propiedad.Estado__c, false);
      return;
    }

    propiedad.Estado_de_Cierre_Legal__c = 'Rechazado';
    propiedad.Ultimo_Error_Integracion__c = null;
    update as user propiedad;
    responder(200, propiedad.Id, propiedad.Estado__c, true);
  }

  private static ResultadoPayload leerPayload(RestRequest solicitud) {
    String cuerpo = solicitud.requestBody?.toString();
    if (String.isBlank(cuerpo)) {
      throw new SolicitudInvalidaException(
        'El cuerpo de la solicitud está vacío.'
      );
    }

    ResultadoPayload payload;
    try {
      payload = (ResultadoPayload) JSON.deserialize(
        cuerpo,
        ResultadoPayload.class
      );
    } catch (JSONException e) {
      throw new SolicitudInvalidaException(
        'El JSON no es válido: ' + e.getMessage()
      );
    }

    if (
      payload == null ||
      (payload.estadoLegal != 'Aprobado' &&
      payload.estadoLegal != 'Rechazado')
    ) {
      throw new SolicitudInvalidaException(
        'estadoLegal debe ser Aprobado o Rechazado: son los únicos resultados que Legal puede informar.'
      );
    }
    return payload;
  }

  // Verifica que sea un Id válido y que pertenezca a Propiedad__c, para
  // que no se pueda apuntar el cierre a un registro de otro objeto.
  private static Id leerId(String texto) {
    try {
      Id propiedadId = Id.valueOf(texto);
      if (propiedadId.getSObjectType() != Propiedad__c.SObjectType) {
        throw new SolicitudInvalidaException(
          'idPropiedadOrigen no corresponde a una propiedad.'
        );
      }
      return propiedadId;
    } catch (StringException e) {
      throw new SolicitudInvalidaException(
        'idPropiedadOrigen no es un Id de Salesforce válido.'
      );
    }
  }

  private static void responder(
    Integer codigo,
    Id propiedadId,
    String estado,
    Boolean huboCambio
  ) {
    escribir(
      codigo,
      new Map<String, Object>{
        'idPropiedad' => propiedadId,
        'estado' => estado,
        'huboCambio' => huboCambio
      }
    );
  }

  private static void escribir(Integer codigo, Map<String, Object> cuerpo) {
    RestResponse respuesta = RestContext.response;
    respuesta.statusCode = codigo;
    respuesta.addHeader('Content-Type', 'application/json');
    respuesta.responseBody = Blob.valueOf(JSON.serialize(cuerpo));
  }
}
