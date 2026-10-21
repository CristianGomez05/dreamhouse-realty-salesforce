@isTest
private class CierreRestServiceTest {
  private static final String ID_PROPIEDAD = 'a01000000000001AAA';

  // El endpoint usa modo usuario, así que se ejecuta como un usuario de
  // prueba que solo tiene el permission set de integración, igual que el
  // usuario real de la External Client App.
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
      WHERE Name = 'Cierre_Integracion'
      LIMIT 1
    ];

    // Se aísla con runAs para evitar MIXED_DML_OPERATION.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      User integracion = new User(
        FirstName = 'Integración',
        LastName = 'Test',
        Email = 'integracion.test@dreamhouse-practica.com',
        Username = 'integracion.test@dreamhouse-practica.com.test',
        Alias = 'integT',
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

  private static String cuerpo(String idPropiedad, Decimal monto) {
    return JSON.serialize(
      new Map<String, Object>{
        'idPropiedadOrigen' => idPropiedad,
        'nombrePropiedad' => 'Villa de Prueba',
        'montoFinal' => monto,
        'compradorNombre' => 'Comprador de prueba'
      }
    );
  }

  private static RestResponse enviar(String cuerpoJson) {
    RestRequest solicitud = new RestRequest();
    solicitud.requestURI = '/services/apexrest/cierre/v1/';
    solicitud.httpMethod = 'POST';
    solicitud.requestBody = Blob.valueOf(cuerpoJson);
    RestContext.request = solicitud;
    RestContext.response = new RestResponse();
    User integracion = [
      SELECT Id
      FROM User
      WHERE Username = 'integracion.test@dreamhouse-practica.com.test'
      LIMIT 1
    ];
    System.runAs(integracion) {
      CierreRestService.doPost();
    }

    // Un 500 es un fallo inesperado del código: se muestra el motivo
    // en lugar de dejar que otra aserción falle sin explicación.
    RestResponse respuesta = RestContext.response;
    System.assert(
      respuesta.statusCode < 500,
      'Error inesperado: ' + respuesta.responseBody.toString()
    );
    return respuesta;
  }

  private static List<Cierre__c> cierres() {
    return [
      SELECT Id, Estado_Legal__c, Monto_Final__c, Comprador_Nombre__c
      FROM Cierre__c
      WHERE Id_Propiedad_Origen__c = :ID_PROPIEDAD
      WITH SYSTEM_MODE
    ];
  }

  @isTest
  static void testCreaUnCierreNuevo() {
    RestResponse respuesta = enviar(cuerpo(ID_PROPIEDAD, 100000));

    System.assertEquals(201, respuesta.statusCode);
    List<Cierre__c> resultado = cierres();
    System.assertEquals(1, resultado.size());
    System.assertEquals('Recibido', resultado[0].Estado_Legal__c);
    System.assertEquals(100000, resultado[0].Monto_Final__c);
    System.assertEquals(
      'Comprador de prueba',
      resultado[0].Comprador_Nombre__c
    );
  }

  @isTest
  static void testReenvioNoDuplicaElCierre() {
    enviar(cuerpo(ID_PROPIEDAD, 100000));
    RestResponse segunda = enviar(cuerpo(ID_PROPIEDAD, 100000));

    System.assertEquals(200, segunda.statusCode);
    System.assertEquals(1, cierres().size(), 'No debe duplicar el cierre');
  }

  @isTest
  static void testReenvioActualizaMientrasLegalNoDecide() {
    enviar(cuerpo(ID_PROPIEDAD, 100000));
    enviar(cuerpo(ID_PROPIEDAD, 95000));

    System.assertEquals(95000, cierres()[0].Monto_Final__c);
  }

  @isTest
  static void testReenvioNoPisaUnCierreYaAprobado() {
    enviar(cuerpo(ID_PROPIEDAD, 100000));
    Cierre__c cierre = cierres()[0];
    cierre.Estado_Legal__c = 'Aprobado';
    Database.update(cierre, AccessLevel.SYSTEM_MODE);

    RestResponse respuesta = enviar(cuerpo(ID_PROPIEDAD, 50000));

    System.assertEquals(200, respuesta.statusCode);
    Cierre__c resultado = cierres()[0];
    System.assertEquals(100000, resultado.Monto_Final__c);
    System.assertEquals('Aprobado', resultado.Estado_Legal__c);
  }

  @isTest
  static void testRechazaSolicitudesInvalidas() {
    List<String> cuerposInvalidos = new List<String>{
      '',
      'esto no es json',
      cuerpo('corto', 100000),
      cuerpo(ID_PROPIEDAD, 0),
      cuerpo(ID_PROPIEDAD, -5)
    };

    for (String invalido : cuerposInvalidos) {
      RestResponse respuesta = enviar(invalido);
      System.assertEquals(
        400,
        respuesta.statusCode,
        'Debe rechazar: ' + invalido
      );
      System.assert(
        respuesta.responseBody.toString().contains('error'),
        'Debe explicar el motivo'
      );
    }
    System.assertEquals(0, cierres().size(), 'No debe crear nada');
  }
}
