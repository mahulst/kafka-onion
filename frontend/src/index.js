import './main.css';
import { Elm } from './Main.elm';
import registerServiceWorker from './registerServiceWorker';

Elm.Main.init({
    node: document.getElementById('root'),
    flags: { apiUrl: process.env.ELM_APP_API_URL || '' },
});

registerServiceWorker();
