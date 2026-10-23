@isTest
private class EnviarCierreQueueableTest {
  // Simula a Org B. También verifica que el cliente llame con POST y a
  // través de la Named Credential, no a una URL escrita en el código.
  private class MockOrgB implements HttpCalloutMock {
    private final Integer codigo;
    private final String cuerpo;

    MockOrgB(Integer codigo, String cuerpo) {
      this.codigo = codigo;
      this.cuerpo = cuerpo;
    }

    public HttpResponse respond(HttpRequest solicitud) {
      System.assertEquals('POST', solicitud.getMethod(), 'Debe ser POST');
      System.assert(
        solicitud.getEndpoint().startsWith('callout:OrgB_Cierre/'),
        'Debe usar la Named Credential: ' + solicitud.getEndpoint()
      );
      HttpResponse respuesta = new HttpResponse();
      respuesta.setStatusCode(codigo);
      respuesta.setBody(cuerpo);
      return respuesta;
    }
  }

  // El monto equivale al 100 % del precio de lista, igual que en
  // PrevenirEliminacionPropiedadTest: cumple la Validation Rule y queda
  // fuera de los umbrales de los Flows. La oferta se inserta ya en
  // Aceptada (el Flow de aceptación solo corre al actualizar).
  private static Propiedad__c crearPropiedad(
    String nombre,
    Boolean conOfertaAceptada
  ) {
    Propiedad__c propiedad = new Propiedad__c(
      Name = nombre,
      Estado__c = 'Activa',
      Region__c = 'Norte',
      Precio_de_Lista__c = 100000
    );
    insert propiedad;

    if (conOfertaAceptada) {
      Comprador__c comprador = new Comprador__c(
        Name = 'Comprador de prueba',
        Region__c = 'Norte'
      );
      insert comprador;
      insert new Oferta__c(
        Propiedad__c = propiedad.Id,
        Comprador__c = comprador.Id,
        Estado__c = 'Aceptada',
        Monto_de_la_Oferta__c = 100000
      );
    }
    return propiedad;
  }

  // Lectura en modo sistema: los campos de control llegaron por
  // despliegue y el usuario que ejecuta la prueba no los ve por FLS.
  private static Propiedad__c recargar(Id propiedadId) {
    return [
      SELECT Id, Estado_de_Cierre_Legal__c, Ultimo_Error_Integracion__c
      FROM Propiedad__c
      WHERE Id = :propiedadId
      WITH SYSTEM_MODE
    ];
  }

  // Deja una oferta con una aprobación pendiente. Si el Flow de aprobación ya
  // la envió al insertarla, no se vuelve a enviar.
  private static void ponerOfertaEnAprobacion(Id ofertaId) {
    Integer pendientes = [
      SELECT COUNT()
      FROM ProcessInstance
      WHERE Status = 'Pending' AND TargetObjectId = :ofertaId
    ];
    if (pendientes == 0) {
      Approval.ProcessSubmitRequest solicitud = new Approval.ProcessSubmitRequest();
      solicitud.setObjectId(ofertaId);
      solicitud.setProcessDefinitionNameOrId('Aprobacion_por_Descuento_Alto');
      Approval.process(solicitud);
    }
  }

  @isTest
  static void testArmarPayloadIncluyeLosDatosDelCierre() {
    Propiedad__c propiedad = crearPropiedad('Casa del Cierre', true);

    CierreVentaCliente.CierrePayload payload = CierreVentaCliente.armarPayload(
      propiedad.Id
    );

    System.assertEquals(
      String.valueOf(propiedad.Id),
      payload.idPropiedadOrigen
    );
    System.assertEquals('Casa del Cierre', payload.nombrePropiedad);
    System.assertEquals(100000, payload.montoFinal);
    System.assertEquals('Comprador de prueba', payload.compradorNombre);
  }

  @isTest
  static void testArmarPayloadFallaSinOfertaAceptada() {
    Propiedad__c propiedad = crearPropiedad('Casa sin oferta', false);

    String mensajeError;
    try {
      CierreVentaCliente.armarPayload(propiedad.Id);
    } catch (CierreVentaCliente.CierreException e) {
      mensajeError = e.getMessage();
    }

    System.assertNotEquals(null, mensajeError, 'Debe lanzar la excepción');
    System.assert(
      mensajeError.contains('oferta aceptada'),
      'Mensaje inesperado: ' + mensajeError
    );
  }

  @isTest
  static void testArmarPayloadFallaSiLaPropiedadNoExiste() {
    Propiedad__c propiedad = crearPropiedad('Casa borrada', false);
    delete propiedad;

    String mensajeError;
    try {
      CierreVentaCliente.armarPayload(propiedad.Id);
    } catch (CierreVentaCliente.CierreException e) {
      mensajeError = e.getMessage();
    }

    System.assertNotEquals(null, mensajeError, 'Debe lanzar la excepción');
    System.assert(
      mensajeError.contains('no existe'),
      'Mensaje inesperado: ' + mensajeError
    );
  }

  @isTest
  static void testEnvioExitosoMarcaEnviado() {
    Propiedad__c propiedad = crearPropiedad('Casa exitosa', true);
    Test.setMock(HttpCalloutMock.class, new MockOrgB(200, '{}'));

    Test.startTest();
    System.enqueueJob(new EnviarCierreQueueable(propiedad.Id, 1));
    Test.stopTest();

    Propiedad__c resultado = recargar(propiedad.Id);
    System.assertEquals('Enviado', resultado.Estado_de_Cierre_Legal__c);
    System.assertEquals(null, resultado.Ultimo_Error_Integracion__c);
  }

  @isTest
  static void testFalloEnUltimoIntentoMarcaError() {
    Propiedad__c propiedad = crearPropiedad('Casa con fallo', true);
    Test.setMock(HttpCalloutMock.class, new MockOrgB(500, 'servidor caido'));

    Test.startTest();
    System.enqueueJob(
      new EnviarCierreQueueable(
        propiedad.Id,
        EnviarCierreQueueable.MAX_INTENTOS
      )
    );
    Test.stopTest();

    Propiedad__c resultado = recargar(propiedad.Id);
    System.assertEquals('Error', resultado.Estado_de_Cierre_Legal__c);
    System.assert(
      resultado.Ultimo_Error_Integracion__c.contains('HTTP 500'),
      'Debe guardar el motivo: ' + resultado.Ultimo_Error_Integracion__c
    );
  }

  @isTest
  static void testSinOfertaAceptadaTerminaEnError() {
    Propiedad__c propiedad = crearPropiedad('Casa sin oferta', false);
    Test.setMock(HttpCalloutMock.class, new MockOrgB(200, '{}'));

    Test.startTest();
    System.enqueueJob(
      new EnviarCierreQueueable(
        propiedad.Id,
        EnviarCierreQueueable.MAX_INTENTOS
      )
    );
    Test.stopTest();

    Propiedad__c resultado = recargar(propiedad.Id);
    System.assertEquals('Error', resultado.Estado_de_Cierre_Legal__c);
    System.assert(
      resultado.Ultimo_Error_Integracion__c.contains('oferta aceptada')
    );
  }

  @isTest
  static void testInvocableSoloEnviaLasPropiedadesElegibles() {
    Propiedad__c elegible = crearPropiedad('Casa elegible', true);
    Propiedad__c yaCerrada = crearPropiedad('Casa ya cerrada', true);
    yaCerrada.Estado_de_Cierre_Legal__c = 'Cerrado';
    Database.update(yaCerrada, AccessLevel.SYSTEM_MODE);
    Test.setMock(HttpCalloutMock.class, new MockOrgB(200, '{}'));

    CierreInvocable.Entrada entradaA = new CierreInvocable.Entrada();
    entradaA.propiedadId = elegible.Id;
    CierreInvocable.Entrada entradaB = new CierreInvocable.Entrada();
    entradaB.propiedadId = yaCerrada.Id;

    Test.startTest();
    CierreInvocable.enviar(
      new List<CierreInvocable.Entrada>{ entradaA, entradaB }
    );
    Test.stopTest();

    System.assertEquals(
      'Enviado',
      recargar(elegible.Id).Estado_de_Cierre_Legal__c
    );
    System.assertEquals(
      'Cerrado',
      recargar(yaCerrada.Id).Estado_de_Cierre_Legal__c,
      'Una propiedad ya cerrada no debe reenviarse'
    );
  }

  @isTest
  static void testInvocableConListaVaciaNoFalla() {
    Test.startTest();
    CierreInvocable.enviar(new List<CierreInvocable.Entrada>());
    Test.stopTest();

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'EnviarCierreQueueable'
      ]
    );
  }

  @isTest
  static void testInvocableNoEnviaSiHayUnaOfertaConAprobacionPendiente() {
    Propiedad__c propiedad = crearPropiedad(
      'Casa con aprobacion pendiente',
      true
    );
    Comprador__c comprador = [SELECT Id FROM Comprador__c LIMIT 1];
    // 80 % del precio de lista: por debajo del 85 %, requiere aprobación.
    Oferta__c conDescuento = new Oferta__c(
      Propiedad__c = propiedad.Id,
      Comprador__c = comprador.Id,
      Estado__c = 'Enviada',
      Monto_de_la_Oferta__c = 80000
    );
    insert conDescuento;
    ponerOfertaEnAprobacion(conDescuento.Id);
    Test.setMock(HttpCalloutMock.class, new MockOrgB(200, '{}'));

    CierreInvocable.Entrada entrada = new CierreInvocable.Entrada();
    entrada.propiedadId = propiedad.Id;

    Test.startTest();
    CierreInvocable.enviar(new List<CierreInvocable.Entrada>{ entrada });
    Test.stopTest();

    Propiedad__c resultado = recargar(propiedad.Id);
    System.assertEquals('Error', resultado.Estado_de_Cierre_Legal__c);
    System.assertEquals(
      CierreInvocable.MOTIVO_APROBACION_PENDIENTE,
      resultado.Ultimo_Error_Integracion__c
    );
  }
}
