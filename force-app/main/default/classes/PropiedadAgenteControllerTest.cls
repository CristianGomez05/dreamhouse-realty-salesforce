@isTest
private class PropiedadAgenteControllerTest {
    
    @TestSetup
    static void setup() {
        Profile perfilAgente = [SELECT Id FROM Profile WHERE Name = 'Agente' LIMIT 1];
        UserRole rolAgente = [SELECT Id FROM UserRole WHERE Name = 'Agente' LIMIT 1];
        
        User agenteA;
        User agenteB;
        
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
        }
        
        Propiedad__c propiedadA = new Propiedad__c(
            Name = 'Propiedad Test Agente A',
        Agente_Asignado__c = agenteA.Id,
        Estado__c = 'Activa',
        Region__c = 'Norte',
        Precio_de_Lista__c = 150000
            );
        insert propiedadA;
        
        // Simulamos el resultado que en producción genera la Sharing Rule
        // por criterio (Región = Norte -> Agentes Norte). La recalculación
        // de ese tipo de regla es asíncrona en la plataforma real y no se
        // completa de forma confiable dentro de una transacción de test
        // unitario, así que insertamos el Share directamente: esto prueba
        // que TU Apex respeta el acceso correctamente, que es lo que te
        // corresponde a ti, no si el motor de sharing de Salesforce
        // funciona (eso ya lo garantiza la plataforma).
        insert new Propiedad__Share(
            ParentId = propiedadA.Id,
        UserOrGroupId = agenteA.Id,
        AccessLevel = 'Read',
        RowCause = Schema.Propiedad__Share.RowCause.Manual
            );
        
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
            SELECT Id FROM User
            WHERE Username = 'agenteA.test@dreamhouse-practica.com.test'
        ];
        
        List<Propiedad__c> resultado;
        
        System.runAs(agenteA) {
            Test.startTest();
            resultado = PropiedadAgenteController.getPropiedadesDelAgente('');
            Test.stopTest();
        }
        
        // Debe ver EXACTAMENTE 1 propiedad: la suya.
        System.assertEquals(1, resultado.size(),
        'El Agente A debería ver únicamente su propia propiedad');
        
        System.assertEquals('Propiedad Test Agente A', resultado[0].Name,
        'La propiedad devuelta debe ser la del Agente A, no otra');
        
        // Confirmamos que la visita futura sí viene en el subquery
        System.assertEquals(1, resultado[0].Visitas__r.size(),
        'La propiedad del Agente A debe traer su visita futura');
    }
    
    @isTest
    static void testBusquedaPorNombreFiltraCorrectamente() {
        User agenteA = [
            SELECT Id FROM User
            WHERE Username = 'agenteA.test@dreamhouse-practica.com.test'
        ];
        
        List<Propiedad__c> resultado;
        
        System.runAs(agenteA) {
            Test.startTest();
            resultado = PropiedadAgenteController.getPropiedadesDelAgente('Agente B');
            Test.stopTest();
        }
        
        // Aunque buscara "Agente B", el filtro de seguridad por Agente_Asignado__c
        // debe ganar siempre: el Agente A nunca ve la propiedad de B,
        // sin importar qué término de búsqueda use.
        System.assertEquals(0, resultado.size(),
        'El Agente A no debe poder "buscar su camino" hacia la propiedad de otro agente');
    }
    
    @isTest
    static void diagnosticoSharing() {
        Propiedad__c prop = [
            SELECT Id FROM Propiedad__c
            WHERE Name = 'Propiedad Test Agente A'
            LIMIT 1
        ];
        
        List<Propiedad__Share> shares = [
            SELECT UserOrGroupId, RowCause, AccessLevel
            FROM Propiedad__Share
            WHERE ParentId = :prop.Id
        ];
        
        User agenteA = [
            SELECT Id FROM User
            WHERE Username = 'agenteA.test@dreamhouse-practica.com.test'
        ];
        List<GroupMember> gm = [
            SELECT Group.Name, Group.Type
            FROM GroupMember
            WHERE UserOrGroupId = :agenteA.Id
        ];
        
        String resultado = '--- SHARES (' + shares.size() + ') ---\n';
        for (Propiedad__Share s : shares) {
            resultado += 'UserOrGroupId=' + s.UserOrGroupId
                + ' | RowCause=' + s.RowCause
                + ' | AccessLevel=' + s.AccessLevel + '\n';
        }
        
        resultado += '--- GRUPOS del Agente A (' + gm.size() + ') ---\n';
        for (GroupMember g : gm) {
            resultado += 'Grupo: ' + g.Group.Name + ' (tipo: ' + g.Group.Type + ')\n';
        }
        
        // Forzamos el fallo a propósito para que el mensaje completo
        // aparezca en el panel de resultados de VS Code.
        System.assert(false, resultado);
    }
}