import './main.css';
import { Elm } from './Main.elm';
import registerServiceWorker from './registerServiceWorker';

const app = Elm.Main.init({
    node: document.getElementById('root'),
    flags: { apiUrl: process.env.ELM_APP_API_URL || '' },
});


app.ports.copy.subscribe((message) => {
    copyToClipboard(message)
});

function copyToClipboard(text) {
    const temp = document.createElement("textarea");
    document.body.appendChild(temp);
    temp.value = text;
    temp.select();
    document.execCommand("copy");
    document.body.removeChild(temp);
}

registerServiceWorker();
