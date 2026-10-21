/**
 * Punto de entrada para el Flow "Notificar Cierre a Origen". Solo encola
 * la notificación. Ignora los cierres que no están Aprobados o que ya
 * fueron notificados, para que reactivar el Flow no duplique la llamada.
 *
 * Límite conocido: Salesforce permite 50 encolados por transacción.
 * El Flow actúa sobre un cierre por vez, por lo que no se alcanza.
 */
public with sharing class CierreAprobadoInvocable {
  public class Entrada {
    @InvocableVariable(label='Id del cierre' required=true)
    public Id cierreId;
  }

  @InvocableMethod(
    label='Notificar cierre aprobado a Org A'
    description='Encola la notificación del cierre aprobado a Org A'
  )
  public static void notificar(List<Entrada> entradas) {
    Set<Id> ids = new Set<Id>();
    for (Entrada entrada : entradas) {
      if (entrada != null && entrada.cierreId != null) {
        ids.add(entrada.cierreId);
      }
    }
    if (ids.isEmpty()) {
      return;
    }

    for (Cierre__c cierre : [
      SELECT Id
      FROM Cierre__c
      WHERE
        Id IN :ids
        AND Estado_Legal__c = 'Aprobado'
        AND (Notificacion_a_Origen__c = NULL
        OR Notificacion_a_Origen__c IN ('Pendiente', 'Error'))
      WITH SYSTEM_MODE
    ]) {
      System.enqueueJob(new NotificarCierreQueueable(cierre.Id, 1));
    }
  }
}
