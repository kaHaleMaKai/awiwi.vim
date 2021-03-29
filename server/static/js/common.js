const _ = (expr) => {
  if (typeof expr === "string") {
    return document.querySelector(expr);
  }
  return expr;
}


const asCustomArray = (...arr) => {
  const ret = [...arr];
  ret.except = (expr) => asCustomArray(...ret.filter(el => el !== expr));
  ret.filter_ = (fn) => asCustomArray(...ret.filter(fn));
  ret.addClasses = (...classes) => {
    ret.forEach(el => el.classList.add(...classes))
    return ret;
  };
  ret.removeClasses = (...classes) => {
    ret.forEach(el => el.classList.remove(...classes));
    return ret;
  }
  ret.all = (fn) => ret.filter(fn).length === ret.length;
  ret.any = (fn) => ret.filter(fn).length > 0;
  return ret;
}


const __ = (expr, ...more) => {
  const nodesOrExpressions = [expr];
  nodesOrExpressions.push(...more);

  if (typeof expr === "string") {
    return asCustomArray(...document.querySelectorAll(nodesOrExpressions.join(", ")));
  }
  if (nodesOrExpressions.constructor !== Array) {
    let ret = [nodesOrExpressions];
  }
  else {
    let ret = nodesOrExpressions;
  }
  return asCustomArray(...ret);
}


const log = (expr) => console.log(expr);



let html = document.getElementsByTagName('html')[0];

html.classList.add('color-theme-in-transition');

window.setTimeout(() => {
  document.documentElement.classList.remove('color-theme-in-transition')
}, 1000);

let createCookie = (name, value) => {
    let date = new Date();
    date.setTime(date.getTime() + (9999*24*60*60*1000));
    let expires = "; expires=" + date.toGMTString();
    return name + "=" + value + expires + "; path=/";
}

if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
    html.classList.add('color-theme-in-transition');
    window.setTimeout(() => {
      document.documentElement.classList.remove('color-theme-in-transition')
    }, 1000);
    html.setAttribute('data-theme', 'dark');
    document.cookie = createCookie('theme-mode', 'dark');
    document.getElementById('mode-switcher-input').checked = true;
}

let el = document.getElementById('mode-switcher-input');

window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
    html.classList.add('color-theme-in-transition');
    window.setTimeout(() => {
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

    window.setTimeout(() => {
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

const checkboxHandler = (e) => {
  const that = e.currentTarget;
  const hash = e.currentTarget.getAttribute('data-hash');
  const lineNr = e.currentTarget.getAttribute('data-line-nr');
  const check = e.currentTarget.checked;
  const path = window.location.pathname;
  const body = {path: path, check: check, line_nr: parseInt(lineNr), hash: hash};

  const host = window.location.host;
  const protocol = window.location.protocol;
  const address = protocol + '//' + host + '/checkbox';

  const data = { method: 'PATCH', body: JSON.stringify(body), headers: { 'Content-Type': 'application/json; charset=UTF-8' } };
  fetch(address, data).then(r => r.json()).then(t => {
    if (!t.success) {
      that.checked = !that.checked;
      alert("could not toggle box: " + t.msg);
    }
  });
}

const attachCheckboxes = () => {
  const els = document.getElementsByClassName('awiwi-checkbox');
  for (let i = 0; i < els.length; ++i) {
    const el = els[i];
    el.onclick = checkboxHandler;
  }
}

const addParentClasses = () => {
  const subClasses = ["centered"];
  ["table", "li", "img", "dl"].forEach(type => {
    subClasses.forEach(cls => {
      __(`${type}.${cls}`).forEach(el => {
        if (!el.parentElement.classList.contains(cls)) {
          el.parentElement.classList.add(cls);
        }
      })
    })
  })
}

const onloadHandler = () => {
  attachCheckboxes();
  addParentClasses();
}

const downKeys = new Set();

let mykey = null;

document.addEventListener('keydown', (e) => {
  switch (e.code) {
    case "AltLeft":
    case "ShiftLeft":
    case "KeyE":
      e.preventDefault();
      downKeys.add(e.code);
      mykey = e;
  }
  if (downKeys.size === 3) {
    const switcher = document.getElementById('mode-switcher-input');
    switcher.checked = !switcher.checked;
    themeChanger();
  }
})

document.addEventListener('keyup', (e) => {
  switch (e.code) {
    case "KeyE":
    case "AltLeft":
    case "ShiftLeft":
      downKeys.delete(e.code);
  }
})
