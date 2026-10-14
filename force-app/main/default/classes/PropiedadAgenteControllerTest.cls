@isTest
private class PropiedadAgenteControllerTest {
  @TestSetup
  static void setup() {
    Profile perfilAgente = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Agente'
      LIMIT 1
    ];
    UserRole rolAgente = [
      SELECT Id
      FROM UserRole
      WHERE Name = 'Agente'
      LIMIT 1
    ];

    // Permission Set que otorga el FLS de los campos nuevos (por ejemplo
    // Visita__c.Realizada__c). Con WITH USER_MODE, un usuario sin este
    // permiso recibe una excepción de acceso a campo.
    PermissionSet permisoPanel = [
      SELECT Id
      FROM PermissionSet
      WHERE Label = 'Panel del Agente - Acceso'
      LIMIT 1
    ];

    User agenteA;
    User agenteB;

    // La creación de Users y PermissionSetAssignment (setup objects) se
    // aísla con System.runAs para evitar MIXED_DML_OPERATION al insertar
    // después Propiedad__c y Visita__c (non-setup objects).
    System.runAs(new User(Id = UserInfo.getUserId())) {
      agenteA = new User(
        FirstName = 'Agente',
        LastName = 'Test A',
        Email = 'agenteA.test@dreamhouse-practica.com',
        Username = 'agenteA.test@dreamhouse-practica.com.test',
        Alias = 'agtA',
        TimeZoneSidKey = 'America/Costa_Rica',
        LocaleSidKey = 'es_CR',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'es',
        ProfileId = perfilAgente.Id,
        UserRoleId = rolAgente.Id
      );
      insert agenteA;

      agenteB = new User(
        FirstName = 'Agente',
        LastName = 'Test B',
        Email = 'agenteB.test@dreamhouse-practica.com',
        Username = 'agenteB.test@dreamhouse-practica.com.test',
        Alias = 'agtB',
        TimeZoneSidKey = 'America/Costa_Rica',
        LocaleSidKey = 'es_CR',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'es',
        ProfileId = perfilAgente.Id,
        UserRoleId = rolAgente.Id
      );
      insert agenteB;

      insert new List<PermissionSetAssignment>{
        new PermissionSetAssignment(
          AssigneeId = agenteA.Id,
          PermissionSetId = permisoPanel.Id
        ),
        new PermissionSetAssignment(
          AssigneeId = agenteB.Id,
          PermissionSetId = permisoPanel.Id
        )
      };
    }

    Propiedad__c propiedadA = new Propiedad__c(
      Name = 'Propiedad Test Agente A',
      Agente_Asignado__c = agenteA.Id,
      Estado__c = 'Activa',
      Region__c = 'Norte',
      Precio_de_Lista__c = 150000
    );
    insert propiedadA;

    // Simula el resultado que produce en producción la Sharing Rule por
    // criterio (Región = Norte -> Agentes Norte, Read Only). La
    // recalculación de ese tipo de regla es asíncrona y no se completa de
    // forma confiable dentro de una transacción de test, por lo que los
    // Shares se insertan de forma directa. Ambos agentes de la región
    // reciben lectura sobre la propiedad, igual que en producción.
    insert new List<Propiedad__Share>{
      new Propiedad__Share(
        ParentId = propiedadA.Id,
        UserOrGroupId = agenteA.Id,
        AccessLevel = 'Read',
        RowCause = Schema.Propiedad__Share.RowCause.Manual
      ),
      new Propiedad__Share(
        ParentId = propiedadA.Id,
        UserOrGroupId = agenteB.Id,
        AccessLevel = 'Read',
        RowCause = Schema.Propiedad__Share.RowCause.Manual
      )
    };

    insert new Visita__c(
      Propiedad__c = propiedadA.Id,
      Agente_Asignado__c = agenteA.Id,
      Fecha_de_Visita__c = DateTime.now().addDays(2),
      Notas__c = 'Visita de prueba del Agente A'
    );

    insert new Propiedad__c(
      Name = 'Propiedad Test Agente B',
      Agente_Asignado__c = agenteB.Id,
      Estado__c = 'Activa',
      Region__c = 'Sur',
      Precio_de_Lista__c = 200000
    );
  }

  @isTest
  static void testAgenteVeSoloSuPropiedad() {
    User agenteA = [
      SELECT Id
      FROM User
      WHERE Username = 'agenteA.test@dreamhouse-practica.com.test'
    ];

    List<Propiedad__c> resultado;

    System.runAs(agenteA) {
      Test.startTest();
      resultado = PropiedadAgenteController.getPropiedadesDelAgente('');
      Test.stopTest();
    }

    System.assertEquals(
      1,
      resultado.size(),
      'El Agente A debería ver únicamente su propia propiedad'
    );

    System.assertEquals(
      'Propiedad Test Agente A',
      resultado[0].Name,
      'La propiedad devuelta debe ser la del Agente A, no otra'
    );

    System.assertEquals(
      1,
      resultado[0].Visitas__r.size(),
      'La propiedad del Agente A debe traer su visita futura'
    );
  }

  @isTest
  static void testBusquedaPorNombreFiltraCorrectamente() {
    User agenteA = [
      SELECT Id
      FROM User
      WHERE Username = 'agenteA.test@dreamhouse-practica.com.test'
    ];

    List<Propiedad__c> resultado;

    System.runAs(agenteA) {
      Test.startTest();
      resultado = PropiedadAgenteController.getPropiedadesDelAgente('Agente B');
      Test.stopTest();
    }

    // El filtro de seguridad por Agente_Asignado__c prevalece sobre
    // cualquier término de búsqueda: el Agente A nunca obtiene la
    // propiedad de otro agente.
    System.assertEquals(
      0,
      resultado.size(),
      'El Agente A no debe poder "buscar su camino" hacia la propiedad de otro agente'
    );
  }

  @isTest
  static void testAgenteAsignadoMarcaSuVisitaComoRealizada() {
    User agenteA = [
      SELECT Id
      FROM User
      WHERE Username = 'agenteA.test@dreamhouse-practica.com.test'
    ];
    Visita__c visita = [
      SELECT Id
      FROM Visita__c
      WHERE Propiedad__r.Name = 'Propiedad Test Agente A'
      LIMIT 1
    ];

    System.runAs(agenteA) {
      PropiedadAgenteController.marcarVisitaRealizada(visita.Id);
    }

    Visita__c actualizada = [
      SELECT Realizada__c
      FROM Visita__c
      WHERE Id = :visita.Id
    ];
    System.assertEquals(
      true,
      actualizada.Realizada__c,
      'La visita debe quedar marcada como realizada'
    );
  }

  @isTest
  static void testAgenteNoAsignadoNoPuedeMarcarVisitaAjena() {
    User agenteB = [
      SELECT Id
      FROM User
      WHERE Username = 'agenteB.test@dreamhouse-practica.com.test'
    ];
    Visita__c visita = [
      SELECT Id
      FROM Visita__c
      WHERE Propiedad__r.Name = 'Propiedad Test Agente A'
      LIMIT 1
    ];

    // El Agente B tiene lectura sobre la propiedad, por lo que la
    // visita es visible y el rechazo proviene de la autorización
    // explícita del controller.
    Boolean excepcionLanzada = false;
    System.runAs(agenteB) {
      try {
        PropiedadAgenteController.marcarVisitaRealizada(visita.Id);
      } catch (AuraHandledException e) {
        excepcionLanzada = true;
      }
    }

    System.assertEquals(
      true,
      excepcionLanzada,
      'Un agente sin relación con la visita no debe poder cerrarla'
    );

    Visita__c sinCambios = [
      SELECT Realizada__c
      FROM Visita__c
      WHERE Id = :visita.Id
    ];
    System.assertEquals(
      false,
      sinCambios.Realizada__c,
      'La visita ajena debe permanecer sin cambios'
    );
  }

  @isTest
  static void testIdNuloLanzaExcepcion() {
    Boolean excepcionLanzada = false;
    try {
      PropiedadAgenteController.marcarVisitaRealizada(null);
    } catch (AuraHandledException e) {
      excepcionLanzada = true;
    }
    System.assertEquals(
      true,
      excepcionLanzada,
      'Un identificador nulo debe rechazarse'
    );
  }

  @isTest
  static void testReglaDeValidacionBloqueaEdicionDeColega() {
    User agenteB = [
      SELECT Id
      FROM User
      WHERE Username = 'agenteB.test@dreamhouse-practica.com.test'
    ];
    Visita__c visita = [
      SELECT Id
      FROM Visita__c
      WHERE Propiedad__r.Name = 'Propiedad Test Agente A'
      LIMIT 1
    ];

    String mensajeError;
    System.runAs(agenteB) {
      Visita__c cambio = new Visita__c(
        Id = visita.Id,
        Notas__c = 'Cambio no autorizado'
      );
      try {
        update as user cambio;
      } catch (DmlException e) {
        mensajeError = e.getDmlMessage(0);
      }
    }

    System.assertNotEquals(
      null,
      mensajeError,
      'La edición de una visita ajena debe rechazarse'
    );
    // La verificación del texto confirma que el rechazo proviene de la
    // regla de validación y no de un permiso de campo o de registro.
    System.assert(
      mensajeError.contains('Solo el agente asignado'),
      'El rechazo debe provenir de la regla de validación: ' + mensajeError
    );

    Visita__c sinCambios = [
      SELECT Notas__c
      FROM Visita__c
      WHERE Id = :visita.Id
    ];
    System.assertEquals(
      'Visita de prueba del Agente A',
      sinCambios.Notas__c,
      'Las notas de la visita ajena deben permanecer sin cambios'
    );
  }

  @isTest
  static void testReglaDeValidacionBloqueaAutoAsignacionDeVisitaAjena() {
    User agenteB = [
      SELECT Id
      FROM User
      WHERE Username = 'agenteB.test@dreamhouse-practica.com.test'
    ];
    Visita__c visita = [
      SELECT Id
      FROM Visita__c
      WHERE Propiedad__r.Name = 'Propiedad Test Agente A'
      LIMIT 1
    ];

    // Intento de eludir la regla: reasignarse la visita en la misma
    // edición. La regla compara contra el agente asignado previo.
    String mensajeError;
    System.runAs(agenteB) {
      Visita__c cambio = new Visita__c(
        Id = visita.Id,
        Agente_Asignado__c = agenteB.Id
      );
      try {
        update as user cambio;
      } catch (DmlException e) {
        mensajeError = e.getDmlMessage(0);
      }
    }

    System.assertNotEquals(
      null,
      mensajeError,
      'La auto-asignación de una visita ajena debe rechazarse'
    );
    System.assert(
      mensajeError.contains('Solo el agente asignado'),
      'El rechazo debe provenir de la regla de validación: ' + mensajeError
    );
  }

  @isTest
  static void testVisitaInexistenteLanzaExcepcion() {
    User agenteA = [
      SELECT Id
      FROM User
      WHERE Username = 'agenteA.test@dreamhouse-practica.com.test'
    ];
    Visita__c visita = [
      SELECT Id
      FROM Visita__c
      WHERE Propiedad__r.Name = 'Propiedad Test Agente A'
      LIMIT 1
    ];

    // Se elimina el registro para que el identificador sea válido pero
    // ya no exista.
    delete visita;

    String mensajeError;
    System.runAs(agenteA) {
      try {
        PropiedadAgenteController.marcarVisitaRealizada(visita.Id);
      } catch (AuraHandledException e) {
        mensajeError = e.getMessage();
      }
    }

    System.assertNotEquals(
      null,
      mensajeError,
      'Una visita inexistente debe rechazarse'
    );
    System.assert(
      mensajeError.contains('no existe'),
      'El mensaje debe indicar que la visita no existe: ' + mensajeError
    );
  }

  @isTest
  static void testVisitaYaRealizadaNoSeProcesaDeNuevo() {
    User agenteA = [
      SELECT Id
      FROM User
      WHERE Username = 'agenteA.test@dreamhouse-practica.com.test'
    ];
    Visita__c visita = [
      SELECT Id
      FROM Visita__c
      WHERE Propiedad__r.Name = 'Propiedad Test Agente A'
      LIMIT 1
    ];
    update new Visita__c(Id = visita.Id, Realizada__c = true);

    Integer dmlAntes;
    Integer dmlDespues;
    System.runAs(agenteA) {
      dmlAntes = Limits.getDmlStatements();
      PropiedadAgenteController.marcarVisitaRealizada(visita.Id);
      dmlDespues = Limits.getDmlStatements();
    }

    // La operación idempotente retorna antes de cualquier DML.
    System.assertEquals(
      dmlAntes,
      dmlDespues,
      'Una visita ya realizada no debe generar una nueva operación DML'
    );

    Visita__c resultado = [
      SELECT Realizada__c
      FROM Visita__c
      WHERE Id = :visita.Id
    ];
    System.assertEquals(
      true,
      resultado.Realizada__c,
      'La visita debe seguir marcada como realizada'
    );
  }
}
