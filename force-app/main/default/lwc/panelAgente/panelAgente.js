import { LightningElement, track, wire } from 'lwc';
import getPropiedadesDelAgente from '@salesforce/apex/PropiedadAgenteController.getPropiedadesDelAgente';

export default class PanelAgente extends LightningElement {

    @track searchTerm = '';
    @track propiedades = [];
    @track errorMensaje;
    @track cargando = true;

    // Variable interna para el debounce — no es reactiva (no @track),
    // porque solo guarda la referencia al temporizador, no algo que
    // deba disparar un re-render.
    debounceTimeout;

    // @wire se re-ejecuta automáticamente cada vez que searchTerm
    // cambia. El prefijo "$" es lo que lo hace reactivo: sin él,
    // Lightning solo leería el valor una vez, en el momento en que
    // el componente se crea.
    @wire(getPropiedadesDelAgente, { terminoBusqueda: '$searchTerm' })
    wiredPropiedades({ data, error }) {
        this.cargando = false;

        if (data) {
            this.propiedades = data.map((prop) => ({
                ...prop,
                cantidadVisitas: prop.Visitas__r ? prop.Visitas__r.length : 0,
                tieneOfertas: prop.Total_de_Ofertas__c > 0
            }));
            this.errorMensaje = undefined;
        } else if (error) {
            this.errorMensaje = this.extraerMensajeError(error);
            this.propiedades = [];
        }
    }

    handleBusquedaChange(event) {
        // Guardamos el valor del input YA (para que el campo de texto
        // no se sienta "trabado"), pero NO actualizamos searchTerm
        // todavía — eso es lo que retrasa la consulta a Apex.
        const valorEscrito = event.target.value;

        // Si había un temporizador pendiente de una tecla anterior,
        // lo cancelamos. Esto es el corazón del debounce: cada tecla
        // reinicia la cuenta regresiva.
        clearTimeout(this.debounceTimeout);

        this.debounceTimeout = setTimeout(() => {
            // Esta función interna es un closure: "recuerda" la
            // referencia a `this` del componente y a `valorEscrito`,
            // aunque handleBusquedaChange ya haya terminado de
            // ejecutarse hace 300ms.
            this.cargando = true;
            this.searchTerm = valorEscrito;
        }, 300);
    }

    extraerMensajeError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'Ocurrió un error al cargar las propiedades.';
    }

    get hayPropiedades() {
        return this.propiedades && this.propiedades.length > 0;
    }

    get mostrarMensajeVacio() {
        return !this.cargando && !this.errorMensaje && !this.hayPropiedades;
    }
}