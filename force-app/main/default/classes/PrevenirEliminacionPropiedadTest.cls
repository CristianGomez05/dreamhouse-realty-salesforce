@isTest
private class PrevenirEliminacionPropiedadTest {
  private static Propiedad__c crearPropiedad(String nombre) {
    Propiedad__c propiedad = new Propiedad__c(
      Name = nombre,
      Estado__c = 'Activa',
      Region__c = 'Norte',
      Precio_de_Lista__c = 100000
    );
    insert propiedad;
    return propiedad;
  }

  private static Comprador__c crearComprador() {
    Comprador__c comprador = new Comprador__c(
      Name = 'Comprador de prueba',
      Region__c = 'Norte'
    );
    insert comprador;
    return comprador;
  }

  // El monto equivale al 100 % del precio de lista: cumple el mínimo de la
  // Validation Rule y queda fuera de los umbrales de los Flows de
  // aprobación (menor a 85 %) y de sobreprecio (mayor a 100 %), de modo que
  // la prueba no depende de esa automatización.
  private static Oferta__c crearOferta(
    Id propiedadId,
    Id compradorId,
    String estado
  ) {
    Oferta__c oferta = new Oferta__c(
      Propiedad__c = propiedadId,
      Comprador__c = compradorId,
      Estado__c = estado,
      Monto_de_la_Oferta__c = 100000
    );
    insert oferta;
    return oferta;
  }

  @isTest
  static void testBloqueaEliminacionConOfertaEnviada() {
    Propiedad__c propiedad = crearPropiedad('Propiedad con oferta enviada');
    Comprador__c comprador = crearComprador();
    crearOferta(propiedad.Id, comprador.Id, 'Enviada');

    String mensajeError;
    try {
      delete propiedad;
    } catch (DmlException e) {
      mensajeError = e.getDmlMessage(0);
    }

    System.assertNotEquals(
      null,
      mensajeError,
      'La eliminación debe bloquearse'
    );
    System.assert(
      mensajeError.contains('Ofertas en estado Enviada'),
      'El mensaje debe provenir del trigger: ' + mensajeError
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Propiedad__c WHERE Id = :propiedad.Id],
      'La propiedad debe seguir existiendo'
    );
  }

  @isTest
  static void testPermiteEliminarPropiedadSinOfertas() {
    Propiedad__c propiedad = crearPropiedad('Propiedad sin ofertas');

    delete propiedad;

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Propiedad__c WHERE Id = :propiedad.Id],
      'Una propiedad sin ofertas debe poder eliminarse'
    );
  }

  @isTest
  static void testPermiteEliminarPropiedadConOfertasNoEnviadas() {
    Propiedad__c propiedad = crearPropiedad('Propiedad con oferta rechazada');
    Comprador__c comprador = crearComprador();
    crearOferta(propiedad.Id, comprador.Id, 'Rechazada');

    delete propiedad;

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Propiedad__c WHERE Id = :propiedad.Id],
      'Solo las ofertas en estado Enviada deben bloquear la eliminación'
    );
  }

  @isTest
  static void testEliminacionEnLoteBloqueaSoloLaPropiedadAfectada() {
    Propiedad__c conOferta = crearPropiedad('Lote con oferta enviada');
    Propiedad__c sinOferta = crearPropiedad('Lote sin ofertas');
    Comprador__c comprador = crearComprador();
    crearOferta(conOferta.Id, comprador.Id, 'Enviada');

    // allOrNone = false: cada registro se evalúa de forma independiente.
    List<Database.DeleteResult> resultados = Database.delete(
      new List<Propiedad__c>{ conOferta, sinOferta },
      false
    );

    System.assertEquals(
      false,
      resultados[0].isSuccess(),
      'La propiedad con oferta enviada debe rechazarse'
    );
    System.assert(
      resultados[0].getErrors()[0]
        .getMessage()
        .contains('Ofertas en estado Enviada'),
      'El rechazo debe provenir del trigger'
    );
    System.assertEquals(
      true,
      resultados[1].isSuccess(),
      'La propiedad sin ofertas debe eliminarse en la misma operación'
    );

    System.assertEquals(
      1,
      [SELECT COUNT() FROM Propiedad__c WHERE Id = :conOferta.Id]
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Propiedad__c WHERE Id = :sinOferta.Id]
    );
  }
}
