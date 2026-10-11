import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPropiedadesDelAgente from '@salesforce/apex/PropiedadAgenteController.getPropiedadesDelAgente';
import marcarVisitaRealizada from '@salesforce/apex/PropiedadAgenteController.marcarVisitaRealizada';

export default class PanelAgente extends LightningElement {

    @track searchTerm = '';
    @track propiedades = [];
    @track errorMensaje;
    @track cargando = true;

    debounceTimeout;
    resultadoWire;

    @wire(getPropiedadesDelAgente, { terminoBusqueda: '$searchTerm' })
    wiredPropiedades(resultado) {
        // Se conserva la respuesta completa del wire: refreshApex
        // requiere ese objeto para invalidar la caché del cliente.
        this.resultadoWire = resultado;
        const { data, error } = resultado;
        this.cargando = false;

        if (data) {
            this.propiedades = data.map((prop) => {
                const visitas = prop.Visitas__r
                    ? prop.Visitas__r.map((v) => ({ ...v, procesando: false }))
                    : [];
                return {
                    ...prop,
                    visitas,
                    cantidadVisitas: visitas.length,
                    tieneOfertas: prop.Total_de_Ofertas__c > 0
                };
            });
            this.errorMensaje = undefined;
        } else if (error) {
            this.errorMensaje = this.extraerMensajeError(error);
            this.propiedades = [];
        }
    }

    handleBusquedaChange(event) {
        const valorEscrito = event.target.value;
        clearTimeout(this.debounceTimeout);
        this.debounceTimeout = setTimeout(() => {
            this.cargando = true;
            this.searchTerm = valorEscrito;
        }, 300);
    }

    async handleMarcarRealizada(event) {
        const visitaId = event.detail.visitaId;

        // Evita envíos duplicados mientras la visita ya está en proceso.
        if (this.estaProcesando(visitaId)) {
            return;
        }

        this.actualizarVisita(visitaId, { procesando: true });

        try {
            await marcarVisitaRealizada({ visitaId });
        } catch (error) {
            // El guardado falló: se revierte el estado de la tarjeta y se
            // informa el motivo devuelto por el servidor.
            this.actualizarVisita(visitaId, { procesando: false });
            this.mostrarToast(
                'No se pudo actualizar la visita',
                this.extraerMensajeError(error),
                'error'
            );
            return;
        }

        // El servidor confirmó el guardado: la visita sale de la lista.
        this.quitarVisita(visitaId);
        this.mostrarToast(
            'Visita realizada',
            'La visita se marcó como realizada.',
            'success'
        );

        // La caché del wire conserva la visita hasta que se invalida. Un
        // fallo aquí no afecta al guardado ya confirmado, por lo que se
        // maneja aparte del bloque anterior.
        try {
            await refreshApex(this.resultadoWire);
        } catch (errorRefresco) {
            // La lista local ya refleja el cambio; no se requiere acción.
        }
    }

    // Aplica cambios a una visita concreta mediante reasignación inmutable
    // del arreglo: LWC detecta cambios por referencia.
    actualizarVisita(visitaId, cambios) {
        this.propiedades = this.propiedades.map((prop) => ({
            ...prop,
            visitas: prop.visitas.map((v) =>
                v.Id === visitaId ? { ...v, ...cambios } : v
            )
        }));
    }

    quitarVisita(visitaId) {
        this.propiedades = this.propiedades.map((prop) => {
            const visitas = prop.visitas.filter((v) => v.Id !== visitaId);
            return { ...prop, visitas, cantidadVisitas: visitas.length };
        });
    }

    estaProcesando(visitaId) {
        return this.propiedades.some((prop) =>
            prop.visitas.some((v) => v.Id === visitaId && v.procesando)
        );
    }

    mostrarToast(titulo, mensaje, variante) {
        this.dispatchEvent(
            new ShowToastEvent({ title: titulo, message: mensaje, variant: variante })
        );
    }

    extraerMensajeError(error) {
        const cuerpo = error && error.body;
        if (Array.isArray(cuerpo)) {
            return cuerpo.map((e) => e.message).join(', ');
        }
        if (cuerpo && cuerpo.message) {
            return cuerpo.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'Ocurrió un error inesperado.';
    }

    get hayPropiedades() {
        return this.propiedades && this.propiedades.length > 0;
    }

    get mostrarMensajeVacio() {
        return !this.cargando && !this.errorMensaje && !this.hayPropiedades;
    }
}