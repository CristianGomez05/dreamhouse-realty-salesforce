/**
 * Controlador para el "Panel del Agente" de DreamHouse Realty.
 * Expone las propiedades asignadas al usuario logueado, junto con
 * sus visitas próximas, respetando el modelo de seguridad existente
 * (OWD Private + Sharing Rules por Región).
 *
 * Nota de diseño: "with sharing" hace cumplir las Sharing Rules
 * (quién PUEDE ver el registro), pero no filtra por "mis propios
 * registros" — eso se hace explícitamente en el WHERE, porque la
 * Sharing Rule es por Región, no por Agente individual.
 */
public with sharing class PropiedadAgenteController {

    @AuraEnabled(cacheable=true)
    public static List<Propiedad__c> getPropiedadesDelAgente(String terminoBusqueda) {

        String termino = String.isBlank(terminoBusqueda)
            ? ''
            : terminoBusqueda.trim();
        String terminoLike = '%' + termino + '%';

        return [
            SELECT Id,
                   Name,
                   Estado__c,
                   Region__c,
                   Precio_de_Lista__c,
                   Oferta_Mas_Alta__c,
                   Total_de_Ofertas__c,
                   (SELECT Id, Fecha_de_Visita__c, Notas__c
                    FROM Visitas__r
                    WHERE Fecha_de_Visita__c >= TODAY
                    ORDER BY Fecha_de_Visita__c ASC)
            FROM Propiedad__c
            WHERE Agente_Asignado__c = :UserInfo.getUserId()
              AND (Name LIKE :terminoLike OR Region__c LIKE :terminoLike)
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 200
        ];
    }
}