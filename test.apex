// 1. Buscar el Id del usuario Agente Prueba
User agente = [
    SELECT Id, Username
    FROM User
    WHERE Username = 'agente.prueba@dreamhouse-practica.com'
    LIMIT 1
];
System.debug('Agente Prueba encontrado: ' + agente.Id);

// 2. Traer 2 propiedades existentes para asignarles el agente
List<Propiedad__c> propiedades = [
    SELECT Id, Name
    FROM Propiedad__c
    LIMIT 2
];

for (Propiedad__c p : propiedades) {
    p.Agente_Asignado__c = agente.Id;
}
update propiedades;
System.debug('Propiedades actualizadas: ' + propiedades.size());

// 3. Crear una Visita futura en la primera propiedad, asignada al mismo agente
Visita__c visita = new Visita__c(
    Propiedad__c = propiedades[0].Id,
    Agente_Asignado__c = agente.Id,
    Fecha_de_Visita__c = DateTime.now().addDays(3),
    Notas__c = 'Visita de prueba creada para validar el Panel del Agente'
);
insert visita;
System.debug('Visita creada: ' + visita.Id);