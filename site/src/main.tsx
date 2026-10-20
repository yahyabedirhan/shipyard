import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import './tokens.css';
import { startAnalytics } from './analytics';
import { startErrorReporting } from './errors';
import { Docs } from './docs/Docs';
import { NotFound, Privacy } from './privacy/Privacy';
import { routeOf } from './route';

startErrorReporting();
const route = routeOf(location.pathname);
const page = route === 'docs' ? <Docs /> : route === 'privacy' ? <Privacy /> : <NotFound />;
createRoot(document.getElementById('root')!).render(<StrictMode>{page}</StrictMode>);
startAnalytics();
