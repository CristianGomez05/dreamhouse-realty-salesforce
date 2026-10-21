/**
 * Punto de entrada para el Flow "Enviar Cierre a Org B". Solo encola el
 * envío; no hace callouts ni DML. Ignora las propiedades que ya fueron
 * enviadas o cerradas, para que reactivar el Flow no duplique el envío.
 *
 * Límite conocido: Salesforce permite 50 encolados por transacción.
 * El Flow actúa sobre una propiedad por vez, por lo que no se alcanza.
 */
public with sharing class CierreInvocable {
  public class Entrada {
    @InvocableVariable(label='Id de la propiedad' required=true)
    public Id propiedadId;
  }

  @InvocableMethod(
    label='Enviar cierre a Org B'
    description='Encola el envío del expediente de cierre a Org B'
  )
  public static void enviar(List<Entrada> entradas) {
    Set<Id> ids = new Set<Id>();
    for (Entrada entrada : entradas) {
      if (entrada != null && entrada.propiedadId != null) {
        ids.add(entrada.propiedadId);
      }
    }
    if (ids.isEmpty()) {
      return;
    }

    for (Propiedad__c propiedad : [
      SELECT Id
      FROM Propiedad__c
      WHERE
        Id IN :ids
        AND (Estado_de_Cierre_Legal__c = NULL
        OR Estado_de_Cierre_Legal__c IN ('Sin enviar', 'Error'))
      WITH SYSTEM_MODE
    ]) {
      System.enqueueJob(new EnviarCierreQueueable(propiedad.Id, 1));
    }
  }
}
