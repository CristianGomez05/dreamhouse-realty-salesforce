import { LightningElement, api } from 'lwc';

export default class TarjetaVisita extends LightningElement {
    @api visita;

    get etiquetaBoton() {
        return this.visita.procesando ? 'Procesando...' : 'Marcar como realizada';
    }

    handleClick() {
        // Comunica la intención al padre sin ejecutar lógica de
        // persistencia aquí: el componente permanece desacoplado
        // de Apex, limitado a presentación e interacción.
        const evento = new CustomEvent('marcarrealizada', {
            detail: { visitaId: this.visita.Id }
        });
        this.dispatchEvent(evento);
    }
}