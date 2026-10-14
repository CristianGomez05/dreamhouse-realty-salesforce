import { createElement } from "lwc";
import { refreshApex } from "@salesforce/apex";
import PanelAgente from "c/panelAgente";
import getPropiedadesDelAgente from "@salesforce/apex/PropiedadAgenteController.getPropiedadesDelAgente";
import marcarVisitaRealizada from "@salesforce/apex/PropiedadAgenteController.marcarVisitaRealizada";

// Adaptador de prueba para el @wire de Apex: permite emitir datos o
// errores desde la prueba y consultar la última configuración recibida.
jest.mock(
  "@salesforce/apex/PropiedadAgenteController.getPropiedadesDelAgente",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// Llamada imperativa: cada prueba define si se resuelve o se rechaza.
jest.mock(
  "@salesforce/apex/PropiedadAgenteController.marcarVisitaRealizada",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

// El stub de lightning/platformShowToastEvent en sfdx-lwc-jest solo exporta
// ShowToastEvent; el tipo del evento se declara de forma literal.
const EVENTO_TOAST = "lightning__showtoast";
const ID_VISITA_1 = "a04000000000001AAA";
const ID_VISITA_2 = "a04000000000002AAA";
const MENSAJE_ERROR =
  "Solo el agente asignado puede marcar la visita como realizada.";

// Se genera una copia nueva por prueba para evitar que una prueba
// altere los datos que usa la siguiente.
function propiedadesMock() {
  return [
    {
      Id: "a01000000000001AAA",
      Name: "Casa Vista al Mar",
      Estado__c: "Bajo Contrato",
      Region__c: "Norte",
      Precio_de_Lista__c: 150000,
      Total_de_Ofertas__c: 6,
      Visitas__r: [
        {
          Id: ID_VISITA_1,
          Fecha_de_Visita__c: "2026-10-15T15:00:00.000Z",
          Notas__c: "Primera visita de prueba",
          Realizada__c: false
        },
        {
          Id: ID_VISITA_2,
          Fecha_de_Visita__c: "2026-10-18T15:00:00.000Z",
          Notas__c: "Segunda visita de prueba",
          Realizada__c: false
        }
      ]
    },
    {
      Id: "a01000000000002AAA",
      Name: "Apartamento Altos del Norte",
      Estado__c: "Nueva",
      Region__c: "Norte",
      Precio_de_Lista__c: 123000,
      Total_de_Ofertas__c: 0
    }
  ];
}

function crearComponente() {
  const element = createElement("c-panel-agente", { is: PanelAgente });
  document.body.appendChild(element);
  return element;
}

// Espera a que se resuelvan promesas y se complete el re-render.
// Requiere temporizadores reales.
function flushPromises() {
  // La regla no-async-operation está pensada para código de componentes;
  // en una prueba, setTimeout es la forma más fiable de vaciar la cola.
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

// Alternativa para pruebas con temporizadores falsos, donde setTimeout
// no puede usarse: solo avanza la cola de microtareas.
async function microtareas() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

function simularMarcarRealizada(element, visitaId) {
  const tarjeta = element.shadowRoot.querySelector("c-tarjeta-visita");
  tarjeta.dispatchEvent(
    new CustomEvent("marcarrealizada", { detail: { visitaId } })
  );
  return tarjeta;
}

describe("c-panel-agente", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.useRealTimers();
    jest.clearAllMocks();
    marcarVisitaRealizada.mockReset();
  });

  it("muestra el mensaje de vacío cuando el wire devuelve una lista vacía", async () => {
    const element = crearComponente();

    getPropiedadesDelAgente.emit([]);
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain(
      "No se encontraron propiedades."
    );
    expect(element.shadowRoot.querySelector("ul")).toBeNull();
  });

  it("renderiza una tarjeta por propiedad y una tarjeta de visita por cada visita", async () => {
    const element = crearComponente();

    getPropiedadesDelAgente.emit(propiedadesMock());
    await flushPromises();

    const nombres = Array.from(
      element.shadowRoot.querySelectorAll(".slds-text-heading_small")
    ).map((nodo) => nodo.textContent);
    expect(nombres).toEqual([
      "Casa Vista al Mar",
      "Apartamento Altos del Norte"
    ]);

    expect(
      element.shadowRoot.querySelectorAll("c-tarjeta-visita")
    ).toHaveLength(2);

    const contadores = Array.from(
      element.shadowRoot.querySelectorAll("lightning-badge")
    ).map((badge) => String(badge.label));
    expect(contadores).toEqual(["2", "0"]);
  });

  it("muestra el error del wire y no renderiza la lista", async () => {
    const element = crearComponente();

    getPropiedadesDelAgente.error();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".slds-text-color_error")
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector("ul")).toBeNull();
  });

  it("retrasa la consulta 300 ms desde la última tecla (debounce)", async () => {
    jest.useFakeTimers();
    const element = crearComponente();
    const input = element.shadowRoot.querySelector("lightning-input");

    // Primera tecla: el temporizador se programa a 300 ms.
    input.value = "casa";
    input.dispatchEvent(new CustomEvent("change"));
    jest.advanceTimersByTime(200);
    await microtareas();
    expect(getPropiedadesDelAgente.getLastConfig()).toEqual({
      terminoBusqueda: ""
    });

    // Segunda tecla a los 200 ms: el temporizador anterior se cancela y
    // se programa uno nuevo. A los 400 ms totales todavía no se cumple.
    input.value = "casa v";
    input.dispatchEvent(new CustomEvent("change"));
    jest.advanceTimersByTime(200);
    await microtareas();
    expect(getPropiedadesDelAgente.getLastConfig()).toEqual({
      terminoBusqueda: ""
    });

    // A los 500 ms totales se cumple el temporizador vigente.
    jest.advanceTimersByTime(100);
    await microtareas();
    expect(getPropiedadesDelAgente.getLastConfig()).toEqual({
      terminoBusqueda: "casa v"
    });
  });

  it("marca la visita como realizada: llama a Apex, quita la tarjeta, notifica y refresca la caché", async () => {
    marcarVisitaRealizada.mockResolvedValue();
    const element = crearComponente();
    const toastHandler = jest.fn();
    element.addEventListener(EVENTO_TOAST, toastHandler);
    getPropiedadesDelAgente.emit(propiedadesMock());
    await flushPromises();

    simularMarcarRealizada(element, ID_VISITA_1);
    await flushPromises();

    expect(marcarVisitaRealizada).toHaveBeenCalledWith({
      visitaId: ID_VISITA_1
    });
    expect(
      element.shadowRoot.querySelectorAll("c-tarjeta-visita")
    ).toHaveLength(1);
    expect(toastHandler).toHaveBeenCalledTimes(1);
    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("success");
    expect(refreshApex).toHaveBeenCalledTimes(1);

    // El contador de la primera propiedad baja de 2 a 1.
    const primerContador = element.shadowRoot.querySelector("lightning-badge");
    expect(String(primerContador.label)).toBe("1");
  });

  it("revierte el estado y muestra el error cuando el guardado falla", async () => {
    marcarVisitaRealizada.mockRejectedValue({
      body: { message: MENSAJE_ERROR }
    });
    const element = crearComponente();
    const toastHandler = jest.fn();
    element.addEventListener(EVENTO_TOAST, toastHandler);
    getPropiedadesDelAgente.emit(propiedadesMock());
    await flushPromises();

    simularMarcarRealizada(element, ID_VISITA_1);
    await flushPromises();

    expect(toastHandler).toHaveBeenCalledTimes(1);
    const toast = toastHandler.mock.calls[0][0].detail;
    expect(toast.variant).toBe("error");
    expect(toast.message).toBe(MENSAJE_ERROR);

    // La visita permanece en la lista y deja de estar en proceso.
    const tarjetas = element.shadowRoot.querySelectorAll("c-tarjeta-visita");
    expect(tarjetas).toHaveLength(2);
    expect(tarjetas[0].visita.procesando).toBe(false);
    expect(refreshApex).not.toHaveBeenCalled();
  });

  it("no envía una segunda solicitud mientras la visita está en proceso", async () => {
    let resolverGuardado;
    marcarVisitaRealizada.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolverGuardado = resolve;
        })
    );
    const element = crearComponente();
    getPropiedadesDelAgente.emit(propiedadesMock());
    await flushPromises();

    const tarjeta = simularMarcarRealizada(element, ID_VISITA_1);
    await flushPromises();
    expect(tarjeta.visita.procesando).toBe(true);

    // Segundo evento sobre la misma visita mientras la primera sigue pendiente.
    simularMarcarRealizada(element, ID_VISITA_1);
    await flushPromises();
    expect(marcarVisitaRealizada).toHaveBeenCalledTimes(1);

    // Al confirmarse el guardado, la visita sale de la lista.
    resolverGuardado();
    await flushPromises();
    expect(
      element.shadowRoot.querySelectorAll("c-tarjeta-visita")
    ).toHaveLength(1);
  });
});
