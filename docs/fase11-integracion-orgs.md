# Fase 11 – Integración Org A ↔ Org B: "Cierre de Venta entre Orgs"

## 1. Necesidad de negocio

Ventas (Org A) cierra una propiedad "Bajo Contrato"; Legal (Org B) debe
formalizar el cierre y devolver el resultado. Sin integración, el cierre se
reenvía por correo y el estado legal en Org A se actualiza a mano.

- **Ida:** Propiedad pasa a "Bajo Contrato" en Org A → se crea/actualiza
  `Cierre__c` en Org B (estado "Recibido").
- **Vuelta:** Legal decide en Org B. Si aprueba, Org A actualiza la propiedad a
  "Cerrada" / `Estado_de_Cierre_Legal__c = Cerrado`. Si rechaza, Org A marca
  `Estado_de_Cierre_Legal__c = Rechazado` y la propiedad sigue en "Bajo
  Contrato"; el agente decide cómo continuar.
- **Panel del Agente:** muestra una insignia con el estado del cierre.

## 2. Autenticación (OAuth 2.0 Client Credentials)

Cada org expone un External Client App con flujo Client Credentials y un
usuario de integración ("Run As"). La org llamante usa:

External Credential (Client Credentials, Client Secret Flow)
→ Principal (Named Principal con Client ID/Secret, cargados solo en Setup)
→ Named Credential (`callout:<Nombre>/...`)
→ Permission Set con acceso al Principal.

| Org llamante | Named Credential | External Credential |
| ------------ | ---------------- | ------------------- |
| A → B        | `OrgB_Cierre`    | `OrgB_Cierre_EC`    |
| B → A        | `OrgA_Cierre`    | `OrgA_Cierre_EC`    |

Ningún secreto vive en el repositorio ni en el código Apex.

## 3. Componentes

**Org A:** `CierreVentaCliente`, `EnviarCierreQueueable`, `CierreInvocable`,
flow `Enviar_Cierre_a_Org_B`, `CierreEntranteRest` (@RestResource), campos
`Estado_de_Cierre_Legal__c` y `Ultimo_Error_Integracion__c`, panel con insignia.

**Org B:** `Cierre__c`, `CierreRestService` (@RestResource, upsert idempotente
por `Id_Propiedad_Origen__c`), `CierreOrigenCliente`,
`NotificarCierreQueueable`, `CierreAprobadoInvocable`, flow
`Notificar_Cierre_a_Origen`.

Manifiestos: `manifest/orgb-fase11.xml` y `manifest/orga-fase11.xml`.

## 4. Qué es declarativo y qué necesitó código

- **Declarativo:** disparo (flows record-triggered), seguridad (permission
  sets, External/Named Credentials), modelo de datos, insignia de estado.
- **Código (Apex):** endpoints de entrada propios con contrato JSON
  validado, idempotencia, reintentos con espera (Queueable), registro del
  último error y control de acceso en modo usuario/sistema.
- Alternativa evaluada: usar la REST API estándar (upsert por External ID)
  desde un callout de Flow. Se descartó porque no valida el contrato ni la
  regla de negocio en el destino, y porque no permite reintentos
  controlados ni registro del error en el registro de origen.

## 5. Reintentos y bucles

- Hasta 3 intentos, con espera de 1 minuto entre ellos
  (`System.enqueueJob(job, 1)`), con guarda de profundidad de cadena.
- Fallo definitivo → estado "Error" y mensaje en `Ultimo_Error_Integracion__c`.
- Sin bucles: los flows disparan solo "cuando se actualiza a cumplir los
  criterios" y la respuesta de vuelta solo toca campos de control.
- **Vuelta:** Legal decide en Org B. Si aprueba, Org A actualiza la propiedad a
  "Cerrada" / `Estado_de_Cierre_Legal__c = Cerrado`. Si rechaza, Org A marca
  `Estado_de_Cierre_Legal__c = Rechazado` y la propiedad sigue en "Bajo
  Contrato"; el agente decide cómo continuar.

## 6. Errores reales y causa raíz

| #   | Síntoma                                                                                         | Causa raíz                                                                                                                                                                                  | Solución                                                                                                                |
| --- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| 1   | El token no se obtiene con el dominio `…salesforce-setup.com`                                   | La URL de Setup no es el dominio de API/token                                                                                                                                               | Usar `…my.salesforce.com`                                                                                               |
| 2   | "Unable to fetch the OAuth token"                                                               | La Identity Provider URL de la External Credential no incluía la ruta del token                                                                                                             | Usar `https://<dominio>.my.salesforce.com/services/oauth2/token`                                                        |
| 3   | "scope parameter not supported"                                                                 | El flujo Client Credentials del External Client App no acepta `scope` enviado por la External Credential                                                                                    | Dejar el campo Scope vacío                                                                                              |
| 4   | 403 `API_DISABLED_FOR_ORG`                                                                      | El usuario de integración no tenía API habilitada                                                                                                                                           | Añadir `ApiEnabled` en el permission set (`Cierre_Integracion`, `Cierre_Entrante_Acceso`)                               |
| 5   | Deploy falla: "Modify All depends on Delete"                                                    | Un permiso Modify All exige Delete sobre el objeto                                                                                                                                          | `allowDelete=true` (compromiso documentado en `Cierre_Entrante_Acceso`)                                                 |
| 6   | Tests: "No such column" / "fields being inaccessible"                                           | El FLS aplica en pruebas a campos recién desplegados                                                                                                                                        | `SYSTEM_MODE` en datos de prueba; `System.runAs` con usuario y permission set para lo que corre en modo usuario         |
| 7   | Test: "uncommitted work pending"                                                                | DML antes de un callout en la misma transacción                                                                                                                                             | Crear datos en `@TestSetup`                                                                                             |
| 8   | Test: "Maximum stack depth has been reached"                                                    | Apex no permite encadenar Queueables en pruebas                                                                                                                                             | Interruptor `@TestVisible encolarReintentos`; el reencolado real se validó en la org (3 intentos)                       |
| 9   | Test: "hasMaxStackDepth is not allowed outside a Queueable"                                     | Solo puede llamarse dentro de un Queueable o Finalizer                                                                                                                                      | Método auxiliar `profundidadMaximaAlcanzada()` con `try/catch`                                                          |
| 10  | CMD no reconoce `\` al final de línea                                                           | La continuación de línea con `\` es sintaxis de bash                                                                                                                                        | Comandos `curl` en una sola línea                                                                                       |
| 11  | ESLint `no-confusing-arrow` en `panelAgente.js`                                                 | Ternario como cuerpo directo de una arrow function                                                                                                                                          | Cuerpo con llaves y `if`/`return`                                                                                       |
| 12  | Validación de Org B: `NO_APPLICABLE_PROCESS` en `PrevenirEliminacionPropiedadTest`              | El flujo `Enviar Oferta a Aprobación Automáticamente` se disparaba con cumplimiento > 0.85 y el proceso de aprobación de Org B solo admite < 0.85: ninguna oferta cumplía ambas condiciones | Cambiar el filtro del flujo a `LessThan 0.85`                                                                           |
| 13  | El correo "Oferta recibida por encima del precio de lista" se enviaba con casi cualquier oferta | El flujo `Notificar_Oferta_por_Encima_del_Precio_de_Lista` comparaba el campo Porcentaje con `1.0`, pero en filtros de flujo el 100 % vale 100                                              | Cambiar el umbral a `100` en ambas orgs. Verificado con el log de depuración (`WF_EMAIL_SENT` solo con ofertas > 100 %) |

## 7. Limitaciones conocidas

- No se bloquea el envío si hay una aprobación de oferta pendiente (mejora
  opcional de negocio).
- `Cierre_Entrante_Acceso` usa Modify All sobre `Propiedad__c`; en
  producción convendría acotarlo con un permiso más fino.
- La rotación de Client Secret es manual (Setup en ambas orgs).
- Org A y Org B tienen definiciones distintas de "Aprobación por Descuento Alto"
  (Org A: cumplimiento > 0.15; Org B: < 0.85). El `ApprovalProcess` del repo es
  el de Org A y no forma parte de los manifiestos. Revisar el flujo equivalente
  de Org A y unificar los criterios.
- Org A y Org B comparten una sola carpeta de código fuente. Por eso el
  manifiesto de Org B, al desplegar el objeto `Propiedad__c`, crearía también
  `Estado_de_Cierre_Legal__c` y `Ultimo_Error_Integracion__c`, que solo se usan
  en Org A. Quedan sin permisos de campo y sin uso. Si molestan, se eliminan a
  mano en Org B.
- Los correos de los flujos salen con remitente `CurrentUser`. Con una dirección
  de Gmail como remitente, Gmail puede descartarlos aunque Salesforce los envíe
  (`WF_EMAIL_SENT`). Para producción convendría una dirección de remitente de
  la organización.

## 8. Despliegue en una org nueva

1. Desplegar el manifiesto de la org correspondiente.
2. Recrear manualmente (no viajan en la metadata): External Client App,
   usuario de integración, Client ID/Secret del Principal de la External
   Credential.
3. Actualizar la URL del dominio en la Named Credential y en la Identity
   Provider URL de la External Credential.
4. Asignar los permission sets (`Cierre_*`, `OrgA_Cierre_Acceso` /
   `OrgB_Cierre_Acceso`).
5. Ejecutar los tests de las clases `Cierre*`, `*Queueable*` y
   `PropiedadAgenteController`.
