@isTest
private class CierreEntranteRestTest {
  private static final String USUARIO = 'integracion.entrante.test@dreamhouse-practica.com.test';

  // El endpoint usa modo usuario: se ejecuta como un usuario de prueba que
  // solo tiene el permission set de integración, igual que el usuario real.
  @TestSetup
  static void setup() {
    Profile perfil = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Minimum Access - Salesforce', 'Standard User')
      ORDER BY Name
      LIMIT 1
    ];
    PermissionSet permiso = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'Cierre_Entrante_Acceso'
      LIMIT 1
    ];

    // Se aísla con runAs para evitar MIXED_DML_OPERATION.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      User integracion = new User(
        FirstName = 'Integración',
        LastName = 'Entrante Test',
        Email = 'integracion.entrante.test@dreamhouse-practica.com',
        Username = USUARIO,
        Alias = 'intE',
        TimeZoneSidKey = 'America/Costa_Rica',
        LocaleSidKey = 'es_CR',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        ProfileId = perfil.Id
      );
      insert integracion;
      insert new PermissionSetAssignment(
        AssigneeId = integracion.Id,
        PermissionSetId = permiso.Id
      );
    }
  }

  private static Propiedad__c crearPropiedad(String estado) {
    Propiedad__c propiedad = new Propiedad__c(
      Name = 'Propiedad entrante ' + estado,
      Estado__c = estado,
      Region__c = 'Norte',
      Precio_de_Lista__c = 100000
    );
    insert propiedad;
    return propiedad;
  }

  private static Propiedad__c recargar(Id propiedadId) {
    return [
      SELECT Id, Estado__c, Estado_de_Cierre_Legal__c
      FROM Propiedad__c
      WHERE Id = :propiedadId
      WITH SYSTEM_MODE
    ];
  }

  private static String cuerpo(String idPropiedad, String estadoLegal) {
    return JSON.serialize(
      new Map<String, Object>{
        'idPropiedadOrigen' => idPropiedad,
        'estadoLegal' => estadoLegal
      }
    );
  }

  private static RestResponse enviar(String cuerpoJson) {
    RestRequest solicitud = new RestRequest();
    solicitud.requestURI = '/services/apexrest/cierre/v1/';
    solicitud.httpMethod = 'PATCH';
    solicitud.requestBody = Blob.valueOf(cuerpoJson);
    RestContext.request = solicitud;
    RestContext.response = new RestResponse();

    User integracion = [SELECT Id FROM User WHERE Username = :USUARIO LIMIT 1];
    System.runAs(integracion) {
      CierreEntranteRest.doPatch();
    }

    // Un 500 es un fallo inesperado del código: se muestra el motivo.
    RestResponse respuesta = RestContext.response;
    System.assert(
      respuesta.statusCode < 500,
      'Error inesperado: ' + respuesta.responseBody.toString()
    );
    return respuesta;
  }

  @isTest
  static void testCierraUnaPropiedadEnBajoContrato() {
    Propiedad__c propiedad = crearPropiedad('Bajo Contrato');

    RestResponse respuesta = enviar(cuerpo(propiedad.Id, 'Aprobado'));

    System.assertEquals(200, respuesta.statusCode);
    Propiedad__c resultado = recargar(propiedad.Id);
    System.assertEquals('Cerrada', resultado.Estado__c);
    System.assertEquals('Cerrado', resultado.Estado_de_Cierre_Legal__c);
  }

  @isTest
  static void testEsIdempotente() {
    Propiedad__c propiedad = crearPropiedad('Bajo Contrato');
    enviar(cuerpo(propiedad.Id, 'Aprobado'));

    RestResponse segunda = enviar(cuerpo(propiedad.Id, 'Aprobado'));

    System.assertEquals(200, segunda.statusCode);
    System.assert(
      segunda.responseBody.toString().contains('"huboCambio":false')
    );
    System.assertEquals('Cerrada', recargar(propiedad.Id).Estado__c);
  }

  @isTest
  static void testRechazaUnaTransicionInvalida() {
    Propiedad__c propiedad = crearPropiedad('Activa');

    RestResponse respuesta = enviar(cuerpo(propiedad.Id, 'Aprobado'));

    System.assertEquals(400, respuesta.statusCode);
    System.assertEquals(
      'Activa',
      recargar(propiedad.Id).Estado__c,
      'No debe cambiar nada'
    );
  }

  @isTest
  static void testRechazaSolicitudesInvalidas() {
    Propiedad__c propiedad = crearPropiedad('Bajo Contrato');
    List<String> cuerposInvalidos = new List<String>{
      '',
      'esto no es json',
      cuerpo('xyz', 'Aprobado'),
      cuerpo(UserInfo.getUserId(), 'Aprobado'),
      cuerpo(propiedad.Id, 'Otro'),
      cuerpo(propiedad.Id, null)
    };

    for (String invalido : cuerposInvalidos) {
      RestResponse respuesta = enviar(invalido);
      System.assertEquals(
        400,
        respuesta.statusCode,
        'Debe rechazar: ' + invalido
      );
    }
    System.assertEquals(
      'Bajo Contrato',
      recargar(propiedad.Id).Estado__c,
      'No debe cambiar nada'
    );
  }

  @isTest
  static void testPropiedadInexistenteDevuelve404() {
    Propiedad__c propiedad = crearPropiedad('Bajo Contrato');
    Id idBorrado = propiedad.Id;
    delete propiedad;

    RestResponse respuesta = enviar(cuerpo(idBorrado, 'Aprobado'));

    System.assertEquals(404, respuesta.statusCode);
  }

  @isTest
  static void testRechazoMarcaLaPropiedadSinCambiarSuEstado() {
    Propiedad__c propiedad = crearPropiedad('Bajo Contrato');

    RestResponse respuesta = enviar(cuerpo(propiedad.Id, 'Rechazado'));

    System.assertEquals(200, respuesta.statusCode);
    Propiedad__c resultado = recargar(propiedad.Id);
    System.assertEquals('Bajo Contrato', resultado.Estado__c);
    System.assertEquals('Rechazado', resultado.Estado_de_Cierre_Legal__c);
  }

  @isTest
  static void testRechazoEsIdempotente() {
    Propiedad__c propiedad = crearPropiedad('Bajo Contrato');
    enviar(cuerpo(propiedad.Id, 'Rechazado'));

    RestResponse segunda = enviar(cuerpo(propiedad.Id, 'Rechazado'));

    System.assertEquals(200, segunda.statusCode);
    System.assert(
      segunda.responseBody.toString().contains('"huboCambio":false')
    );
    System.assertEquals(
      'Rechazado',
      recargar(propiedad.Id).Estado_de_Cierre_Legal__c
    );
  }

  @isTest
  static void testNoSePuedeRechazarUnaPropiedadYaCerrada() {
    Propiedad__c propiedad = crearPropiedad('Bajo Contrato');
    enviar(cuerpo(propiedad.Id, 'Aprobado'));

    RestResponse respuesta = enviar(cuerpo(propiedad.Id, 'Rechazado'));

    System.assertEquals(400, respuesta.statusCode);
    Propiedad__c resultado = recargar(propiedad.Id);
    System.assertEquals('Cerrada', resultado.Estado__c);
    System.assertEquals('Cerrado', resultado.Estado_de_Cierre_Legal__c);
  }

  @isTest
  static void testRechazarUnaPropiedadFueraDeBajoContratoDevuelve400() {
    Propiedad__c propiedad = crearPropiedad('Activa');

    RestResponse respuesta = enviar(cuerpo(propiedad.Id, 'Rechazado'));

    System.assertEquals(400, respuesta.statusCode);
    System.assertNotEquals(
      'Rechazado',
      recargar(propiedad.Id).Estado_de_Cierre_Legal__c,
      'No debe cambiar nada'
    );
  }
}
