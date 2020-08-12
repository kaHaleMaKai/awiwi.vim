let html = document.getElementsByTagName('html')[0];

let createCookie = (name, value) => {
    let date = new Date();
    date.setTime(date.getTime() + (9999*24*60*60*1000));
    let expires = "; expires=" + date.toGMTString();
    return name + "=" + value + expires + "; path=/";
}

if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
    html.classList.add('color-theme-in-transition');
    window.setTimeout(function() {
      document.documentElement.classList.remove('color-theme-in-transition')
    }, 1000);
    html.setAttribute('data-theme', 'dark');
    document.cookie = createCookie('theme-mode', 'dark');
    document.getElementById('mode-switcher-input').checked = true;
}

let el = document.getElementById('mode-switcher-input');

window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
    html.classList.add('color-theme-in-transition');
    window.setTimeout(function() {
      document.documentElement.classList.remove('color-theme-in-transition')
    }, 1000);

    if (e.matches) {
        html.setAttribute('data-theme', 'dark');
        document.cookie = createCookie('theme-mode', 'dark');
        el.checked = true;
    }
    else {
        html.setAttribute('data-theme', 'light');
        document.cookie = createCookie('theme-mode', 'light');
        el.checked = false;
    }
});


let themeChanger = () => {

    let html = document.getElementsByTagName('html')[0];
    html.classList.add('color-theme-in-transition')

    let theme = html.getAttribute('data-theme');

    window.setTimeout(function() {
      document.documentElement.classList.remove('color-theme-in-transition')
    }, 1000);

    if (theme === 'dark') {
        html.removeAttribute('data-theme');
        document.cookie = createCookie('theme-mode', 'light');
    }
    else {
        html.setAttribute('data-theme', 'dark');
        document.cookie = createCookie('theme-mode', 'dark');
    }
}
