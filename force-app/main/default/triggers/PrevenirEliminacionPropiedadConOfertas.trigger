trigger PrevenirEliminacionPropiedadConOfertas on Propiedad__c (before delete) {
    
    // Busca si alguna de las Propiedades que se intentan borrar
    // tiene Ofertas relacionadas en estado "Enviada"
    Set<Id> idsPropiedades = Trigger.oldMap.keySet();
    
    List<Oferta__c> ofertasEnviadas = [
        SELECT Id, Propiedad__c 
        FROM Oferta__c 
        WHERE Propiedad__c IN :idsPropiedades 
        AND Estado__c = 'Enviada'
    ];
    
    // Crea un Set con los Ids de Propiedad que sí tienen ofertas enviadas
    Set<Id> propiedadesConOfertasEnviadas = new Set<Id>();
    for (Oferta__c oferta : ofertasEnviadas) {
        propiedadesConOfertasEnviadas.add(oferta.Propiedad__c);
    }
    
    // Recorre las Propiedades que se intentan borrar y bloque
    // las que aparezcan en el set anterior
    for (Propiedad__c propiedad : Trigger.old) {
        if (propiedadesConOfertasEnviadas.contains(propiedad.Id)) {
            propiedad.addError('No se puede eliminar esta Propiedad porque tiene Ofertas en estado Enviada.');
        }
    }
}