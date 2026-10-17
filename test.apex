Savepoint sp = Database.setSavepoint();
try {
    Propiedad__c propiedad = new Propiedad__c(
        Name = 'Prueba diagnostico',
        Estado__c = 'Activa',
        Region__c = 'Norte',
        Precio_de_Lista__c = 100000
    );
    insert propiedad;

    Comprador__c comprador = new Comprador__c(
        Name = 'Comprador diagnostico',
        Region__c = 'Norte'
    );
    insert comprador;

    Oferta__c oferta = new Oferta__c(
        Propiedad__c = propiedad.Id,
        Comprador__c = comprador.Id,
        Estado__c = 'Enviada',
        Monto_de_la_Oferta__c = 100000
    );
    insert oferta;

    Oferta__c leida = [
        SELECT Porcentaje_de_Descuento__c
        FROM Oferta__c
        WHERE Id = :oferta.Id
    ];
    System.debug('DIAG cumplimiento: ' + leida.Porcentaje_de_Descuento__c);
    System.debug('DIAG solicitudes de aprobacion: ' +
        [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :oferta.Id]);
} catch (Exception e) {
    System.debug('DIAG error: ' + e.getMessage());
}
Database.rollback(sp);