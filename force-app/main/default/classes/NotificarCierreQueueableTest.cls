@isTest
private class NotificarCierreQueueableTest {
  // Simula a Org A. También verifica que se llame con PATCH y a través de
  // la Named Credential, no a una URL escrita en el código.
  private class MockOrgA implements HttpCalloutMock {
    private final Integer codigo;
    private final String cuerpo;

    MockOrgA(Integer codigo, String cuerpo) {
      this.codigo = codigo;
      this.cuerpo = cuerpo;
    }

    public HttpResponse respond(HttpRequest solicitud) {
      System.assertEquals('PATCH', solicitud.getMethod(), 'Debe ser PATCH');
      System.assert(
        solicitud.getEndpoint().startsWith('callout:OrgA_Cierre/'),
        'Debe usar la Named Credential: ' + solicitud.getEndpoint()
      );
      HttpResponse respuesta = new HttpResponse();
      respuesta.setStatusCode(codigo);
      respuesta.setBody(cuerpo);
      return respuesta;
    }
  }

  private static String idOrigen(Integer n) {
    return 'a0100000000000' + String.valueOf(1000 + n);
  }

  // Inserción en modo sistema: los campos nuevos llegaron por despliegue y
  // el usuario que ejecuta la prueba puede no verlos por FLS.
  private static Cierre__c crearCierre(
    Integer n,
    String estadoLegal,
    String notificacion
  ) {
    Cierre__c cierre = new Cierre__c(
      Id_Propiedad_Origen__c = idOrigen(n),
      Nombre_Propiedad__c = 'Villa de Prueba ' + n,
      Monto_Final__c = 100000,
      Estado_Legal__c = estadoLegal,
      Notificacion_a_Origen__c = notificacion
    );
    Database.insert(cierre, AccessLevel.SYSTEM_MODE);
    return cierre;
  }

  private static Cierre__c recargar(Id cierreId) {
    return [
      SELECT Id, Notificacion_a_Origen__c, Ultimo_Error_Integracion__c
      FROM Cierre__c
      WHERE Id = :cierreId
      WITH SYSTEM_MODE
    ];
  }

  @isTest
  static void testPayloadIncluyeElIdYElEstado() {
    Cierre__c cierre = crearCierre(1, 'Aprobado', 'Pendiente');

    CierreOrigenCliente.ResultadoPayload payload = CierreOrigenCliente.armarPayload(
      CierreOrigenCliente.cargarCierre(cierre.Id)
    );

    System.assertEquals(idOrigen(1), payload.idPropiedadOrigen);
    System.assertEquals('Aprobado', payload.estadoLegal);
  }

  @isTest
  static void testPayloadFallaSiElCierreNoEstaAprobado() {
    Cierre__c cierre = crearCierre(2, 'Recibido', 'Pendiente');

    String mensajeError;
    try {
      CierreOrigenCliente.armarPayload(
        CierreOrigenCliente.cargarCierre(cierre.Id)
      );
    } catch (CierreOrigenCliente.CierreException e) {
      mensajeError = e.getMessage();
    }

    System.assertNotEquals(null, mensajeError, 'Debe lanzar la excepción');
    System.assert(
      mensajeError.contains('Aprobado'),
      'Mensaje: ' + mensajeError
    );
  }

  @isTest
  static void testPayloadFallaSinIdDeOrigen() {
    Cierre__c cierre = new Cierre__c(Estado_Legal__c = 'Aprobado');

    String mensajeError;
    try {
      CierreOrigenCliente.armarPayload(cierre);
    } catch (CierreOrigenCliente.CierreException e) {
      mensajeError = e.getMessage();
    }

    System.assertNotEquals(null, mensajeError, 'Debe lanzar la excepción');
    System.assert(mensajeError.contains('origen'), 'Mensaje: ' + mensajeError);
  }

  @isTest
  static void testCargarCierreFallaSiNoExiste() {
    Cierre__c cierre = crearCierre(3, 'Aprobado', 'Pendiente');
    Id idBorrado = cierre.Id;
    Database.delete(cierre, AccessLevel.SYSTEM_MODE);

    String mensajeError;
    try {
      CierreOrigenCliente.cargarCierre(idBorrado);
    } catch (CierreOrigenCliente.CierreException e) {
      mensajeError = e.getMessage();
    }

    System.assertNotEquals(null, mensajeError, 'Debe lanzar la excepción');
  }

  @isTest
  static void testNotificacionExitosaMarcaNotificada() {
    Cierre__c cierre = crearCierre(4, 'Aprobado', 'Pendiente');
    Test.setMock(HttpCalloutMock.class, new MockOrgA(200, '{}'));

    Test.startTest();
    System.enqueueJob(new NotificarCierreQueueable(cierre.Id, 1));
    Test.stopTest();

    Cierre__c resultado = recargar(cierre.Id);
    System.assertEquals('Notificada', resultado.Notificacion_a_Origen__c);
    System.assertEquals(null, resultado.Ultimo_Error_Integracion__c);
  }

  @isTest
  static void testFalloEnUltimoIntentoMarcaError() {
    Cierre__c cierre = crearCierre(5, 'Aprobado', 'Pendiente');
    Test.setMock(HttpCalloutMock.class, new MockOrgA(500, 'servidor caido'));

    Test.startTest();
    System.enqueueJob(
      new NotificarCierreQueueable(
        cierre.Id,
        NotificarCierreQueueable.MAX_INTENTOS
      )
    );
    Test.stopTest();

    Cierre__c resultado = recargar(cierre.Id);
    System.assertEquals('Error', resultado.Notificacion_a_Origen__c);
    System.assert(
      resultado.Ultimo_Error_Integracion__c.contains('Intento 3 de 3'),
      'Debe indicar el intento: ' + resultado.Ultimo_Error_Integracion__c
    );
    System.assert(
      resultado.Ultimo_Error_Integracion__c.contains('HTTP 500'),
      'Debe guardar el motivo: ' + resultado.Ultimo_Error_Integracion__c
    );
  }

  @isTest
  static void testCierreSinAprobarTerminaEnError() {
    Cierre__c cierre = crearCierre(6, 'Recibido', 'Pendiente');
    Test.setMock(HttpCalloutMock.class, new MockOrgA(200, '{}'));

    Test.startTest();
    System.enqueueJob(
      new NotificarCierreQueueable(
        cierre.Id,
        NotificarCierreQueueable.MAX_INTENTOS
      )
    );
    Test.stopTest();

    Cierre__c resultado = recargar(cierre.Id);
    System.assertEquals('Error', resultado.Notificacion_a_Origen__c);
    System.assert(resultado.Ultimo_Error_Integracion__c.contains('Aprobado'));
  }

  @isTest
  static void testInvocableSoloNotificaLosElegibles() {
    Cierre__c elegible = crearCierre(7, 'Aprobado', 'Pendiente');
    Cierre__c yaNotificado = crearCierre(8, 'Aprobado', 'Notificada');
    Cierre__c sinAprobar = crearCierre(9, 'Recibido', 'Pendiente');
    Test.setMock(HttpCalloutMock.class, new MockOrgA(200, '{}'));

    List<CierreAprobadoInvocable.Entrada> entradas = new List<CierreAprobadoInvocable.Entrada>();
    for (
      Cierre__c cierre : new List<Cierre__c>{
        elegible,
        yaNotificado,
        sinAprobar
      }
    ) {
      CierreAprobadoInvocable.Entrada entrada = new CierreAprobadoInvocable.Entrada();
      entrada.cierreId = cierre.Id;
      entradas.add(entrada);
    }

    Test.startTest();
    CierreAprobadoInvocable.notificar(entradas);
    Test.stopTest();

    System.assertEquals(
      'Notificada',
      recargar(elegible.Id).Notificacion_a_Origen__c
    );
    System.assertEquals(
      'Notificada',
      recargar(yaNotificado.Id).Notificacion_a_Origen__c,
      'Un cierre ya notificado no debe reenviarse'
    );
    System.assertEquals(
      'Pendiente',
      recargar(sinAprobar.Id).Notificacion_a_Origen__c,
      'Un cierre sin aprobar no debe notificarse'
    );
  }

  @isTest
  static void testInvocableConListaVaciaNoFalla() {
    Test.startTest();
    CierreAprobadoInvocable.notificar(
      new List<CierreAprobadoInvocable.Entrada>()
    );
    Test.stopTest();

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'NotificarCierreQueueable'
      ]
    );
  }

  @TestSetup
  static void prepararCierreParaReintento() {
    crearCierre(10, 'Aprobado', 'Pendiente');
  }

  @isTest
  static void testFalloIntermedioRegistraElIntentoYNoMarcaError() {
    Cierre__c cierre = [SELECT Id FROM Cierre__c WITH SYSTEM_MODE LIMIT 1];
    Test.setMock(HttpCalloutMock.class, new MockOrgA(500, 'servidor caido'));

    NotificarCierreQueueable.encolarReintentos = false;
    new NotificarCierreQueueable(cierre.Id, 1).execute(null);

    Cierre__c resultado = [
      SELECT Notificacion_a_Origen__c, Ultimo_Error_Integracion__c
      FROM Cierre__c
      WHERE Id = :cierre.Id
      WITH SYSTEM_MODE
    ];
    System.assertNotEquals(
      'Error',
      resultado.Notificacion_a_Origen__c,
      'Un fallo intermedio no debe marcar Error: aún quedan reintentos'
    );
    System.assertNotEquals('Notificada', resultado.Notificacion_a_Origen__c);
    System.assert(
      resultado.Ultimo_Error_Integracion__c.contains('Intento 1 de 3'),
      'Debe quedar registrado el número de intento'
    );
  }
}
