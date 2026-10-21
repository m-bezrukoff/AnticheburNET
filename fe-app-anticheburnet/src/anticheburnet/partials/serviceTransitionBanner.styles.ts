export const serviceTransitionBannerStyles = `
.ac-service-transition[hidden] { display: none; }
.ac-service-transition {
    display: flex;
    align-items: flex-start;
    gap: .75em;
    box-sizing: border-box;
    width: 100%;
    margin: 0 0 1em;
    padding: .85em 1em;
    border: 1px solid var(--border-color-high, #cdd1d6);
    border-radius: 4px;
    background: var(--background-color-high, #f3f4f6);
    color: inherit;
    font: inherit;
    line-height: 1.5;
}
.ac-service-transition__copy { min-width: 0; overflow-wrap: anywhere; }
.ac-service-transition__copy strong { display: block; font-weight: 600; }
.ac-service-transition__detail { display: block; margin-top: .15em; }
.ac-service-transition__spinner {
    flex: 0 0 auto;
    width: 1.4em;
    height: 1.4em;
    margin-top: .1em;
    color: var(--primary-color-high, #006582);
    animation: ac-service-transition-spin 1s linear infinite;
}
@keyframes ac-service-transition-spin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) {
    .ac-service-transition__spinner { animation: none; }
}
`;
