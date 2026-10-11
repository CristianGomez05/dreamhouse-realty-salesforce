User agente = [
    SELECT Id FROM User
    WHERE Username = 'agente.prueba@dreamhouse-practica.com'
    LIMIT 1
];
Propiedad__c vistaAlMar = [
    SELECT Id FROM Propiedad__c
    WHERE Name = 'Casa Vista al Mar'
    LIMIT 1
];
Propiedad__c altosDelNorte = [
    SELECT Id FROM Propiedad__c
    WHERE Name = 'Apartamento Altos del Norte'
    LIMIT 1
];

insert new List<Visita__c>{
    new Visita__c(
        Propiedad__c = vistaAlMar.Id,
        Agente_Asignado__c = agente.Id,
        Fecha_de_Visita__c = DateTime.now().addDays(2),
        Notas__c = 'Primera visita de prueba',
        Realizada__c = false
    ),
    new Visita__c(
        Propiedad__c = vistaAlMar.Id,
        Agente_Asignado__c = agente.Id,
        Fecha_de_Visita__c = DateTime.now().addDays(5),
        Notas__c = 'Segunda visita de prueba',
        Realizada__c = false
    ),
    new Visita__c(
        Propiedad__c = altosDelNorte.Id,
        Agente_Asignado__c = agente.Id,
        Fecha_de_Visita__c = DateTime.now().addDays(3),
        Notas__c = 'Visita en otra propiedad',
        Realizada__c = false
    )
};