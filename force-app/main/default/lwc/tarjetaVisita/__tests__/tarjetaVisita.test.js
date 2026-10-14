import { createElement } from "lwc";
import TarjetaVisita from "c/tarjetaVisita";

const VISITA_BASE = {
  Id: "a04000000000001AAA",
  Fecha_de_Visita__c: "2026-10-15T15:00:00.000Z",
  Notas__c: "Primera visita de prueba",
  procesando: false
};

function crearComponente(visita) {
  const element = createElement("c-tarjeta-visita", { is: TarjetaVisita });
  element.visita = visita;
  document.body.appendChild(element);
  return element;
}

describe("c-tarjeta-visita", () => {
  afterEach(() => {
    // Limpia el DOM entre pruebas para evitar que un componente
    // anterior interfiera con la siguiente.
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("muestra las notas y el botón con la etiqueta por defecto", () => {
    const element = crearComponente({ ...VISITA_BASE });

    const notas = element.shadowRoot.querySelector(".slds-text-color_weak");
    const boton = element.shadowRoot.querySelector("lightning-button");

    expect(notas.textContent).toBe("Primera visita de prueba");
    expect(boton.label).toBe("Marcar como realizada");
    expect(boton.disabled).toBeFalsy();
  });

  it("no renderiza el bloque de notas cuando la visita no tiene notas", () => {
    const element = crearComponente({ ...VISITA_BASE, Notas__c: null });

    const notas = element.shadowRoot.querySelector(".slds-text-color_weak");

    expect(notas).toBeNull();
  });

  it('muestra "Procesando..." y deshabilita el botón mientras la visita está en proceso', () => {
    const element = crearComponente({ ...VISITA_BASE, procesando: true });

    const boton = element.shadowRoot.querySelector("lightning-button");

    expect(boton.label).toBe("Procesando...");
    expect(boton.disabled).toBe(true);
  });

  it("actualiza el botón cuando el padre cambia el estado de procesamiento", async () => {
    const element = crearComponente({ ...VISITA_BASE });

    element.visita = { ...VISITA_BASE, procesando: true };
    // El re-render de LWC es asíncrono: se espera a que la cola de
    // microtareas se vacíe antes de inspeccionar el DOM.
    await Promise.resolve();

    const boton = element.shadowRoot.querySelector("lightning-button");
    expect(boton.label).toBe("Procesando...");
    expect(boton.disabled).toBe(true);
  });

  it("dispara el evento marcarrealizada con el id de la visita al hacer clic", () => {
    const element = crearComponente({ ...VISITA_BASE });
    const manejador = jest.fn();
    element.addEventListener("marcarrealizada", manejador);

    element.shadowRoot.querySelector("lightning-button").click();

    expect(manejador).toHaveBeenCalledTimes(1);
    expect(manejador.mock.calls[0][0].detail).toEqual({
      visitaId: "a04000000000001AAA"
    });
  });
});
