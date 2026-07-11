let currentLanguage = "en";
let translations = {};

async function loadLanguage(language = "en") {
    currentLanguage = language;

    const response = await fetch(`/translations/${language}.json`);
    translations = await response.json();

    applyTranslations();
}

function t(key) {
    return translations[key] || key;
}

function applyTranslations() {
    document.querySelectorAll("[data-i18n]").forEach(el => {
        const key = el.dataset.i18n;
        el.textContent = t(key);
    });
}

document.addEventListener("DOMContentLoaded", () => {
    loadLanguage();
});
