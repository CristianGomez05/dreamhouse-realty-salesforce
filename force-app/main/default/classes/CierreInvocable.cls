/**
 * Punto de entrada para el Flow "Enviar Cierre a Org B". Solo encola el
 * envío; no hace callouts. Ignora las propiedades que ya fueron enviadas,
 * cerradas o rechazadas, para que reactivar el Flow no duplique el envío.
 *
 * Si alguna oferta de la propiedad tiene una aprobación pendiente (proceso
 * "Aprobación por Descuento Alto"), no se envía nada a Org B: la propiedad
 * queda en Error con el motivo, y se puede reenviar después, porque Error
 * es un estado reenviable.
 *
 * Límite conocido: Salesforce permite 50 encolados por transacción.
 * El Flow actúa sobre una propiedad por vez, por lo que no se alcanza.
 */
public with sharing class CierreInvocable {
  @TestVisible
  private static final String MOTIVO_APROBACION_PENDIENTE = 'No se envió el cierre: la propiedad tiene una oferta con aprobación pendiente.';

  public class Entrada {
    @InvocableVariable(label='Id de la propiedad' required=true)
    public Id propiedadId;
  }

  @InvocableMethod(
    label='Enviar cierre a Org B'
    description='Encola el envío del expediente de cierre a Org B, salvo que haya una aprobación de oferta pendiente'
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

    List<Propiedad__c> elegibles = [
      SELECT Id
      FROM Propiedad__c
      WHERE
        Id IN :ids
        AND (Estado_de_Cierre_Legal__c = NULL
        OR Estado_de_Cierre_Legal__c IN ('Sin enviar', 'Error'))
      WITH SYSTEM_MODE
    ];
    if (elegibles.isEmpty()) {
      return;
    }

    Set<Id> idsElegibles = new Map<Id, Propiedad__c>(elegibles).keySet();
    Set<Id> conAprobacionPendiente = propiedadesConAprobacionPendiente(
      idsElegibles
    );

    List<Propiedad__c> bloqueadas = new List<Propiedad__c>();
    for (Propiedad__c propiedad : elegibles) {
      if (conAprobacionPendiente.contains(propiedad.Id)) {
        bloqueadas.add(
          new Propiedad__c(
            Id = propiedad.Id,
            Estado_de_Cierre_Legal__c = 'Error',
            Ultimo_Error_Integracion__c = MOTIVO_APROBACION_PENDIENTE
          )
        );
      } else {
        System.enqueueJob(new EnviarCierreQueueable(propiedad.Id, 1));
      }
    }

    // Campos de control de la integración: se escriben en modo sistema.
    if (!bloqueadas.isEmpty()) {
      Database.update(bloqueadas, AccessLevel.SYSTEM_MODE);
    }
  }

  // Devuelve las propiedades que tienen al menos una oferta con una
  // solicitud de aprobación en estado Pending.
  private static Set<Id> propiedadesConAprobacionPendiente(
    Set<Id> propiedadIds
  ) {
    Map<Id, Id> propiedadPorOferta = new Map<Id, Id>();
    for (Oferta__c oferta : [
      SELECT Id, Propiedad__c
      FROM Oferta__c
      WHERE Propiedad__c IN :propiedadIds
      WITH SYSTEM_MODE
    ]) {
      propiedadPorOferta.put(oferta.Id, oferta.Propiedad__c);
    }

    Set<Id> resultado = new Set<Id>();
    if (propiedadPorOferta.isEmpty()) {
      return resultado;
    }

    for (ProcessInstance instancia : [
      SELECT TargetObjectId
      FROM ProcessInstance
      WHERE
        Status = 'Pending'
        AND TargetObjectId IN :propiedadPorOferta.keySet()
    ]) {
      resultado.add(propiedadPorOferta.get(instancia.TargetObjectId));
    }
    return resultado;
  }
}
