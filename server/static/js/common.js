const THEME_COOKIE_KEY = "awiwi.theme-mode";
let _theme = 'light';

const _ = (expr) => {
  if (typeof expr === "string") {
    return document.querySelector(expr);
  }
  return expr;
}


const range = (start, end) => (new Array(end - start)).fill(undefined).map((_, i) => i + start);


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
  ret.partition = (fn) => {
    const good = asCustomArray(...[]);
    const bad =asCustomArray(...[]);
    ret.forEach(el => {
      if (fn(el)) {
        good.push(el)
      }
      else {
        bad.push(el);
      }
    })
    return asCustomArray(...[good, bad]);
  }
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

const getCookie = (key, defaultValue) => {
  const cookie = document.cookie?.split("; ")
    .find(row => row.trim().startsWith(`${key}=`));
  if (!cookie?.length) {
      return defaultValue;
  }
  return cookie.trim().substr(key.length + 1);
}

const setTheme = (theme) => {
  const isDark = theme === 'dark';
  const modeSwitcher = _("#mode-switcher-input");
  html.setAttribute('data-theme', theme);
  document.cookie = createCookie(THEME_COOKIE_KEY, theme);
  modeSwitcher.checked = isDark;
  _theme = theme;
}

const getTheme = () => html.getAttribute('data-theme', 'light');

const getMermaidTheme = () => getTheme() === 'light' ? 'neutral' : 'dark';

const activateColorSwitching = () => {
  const modeSwitcher = _("#mode-switcher-input");
  const cookieTheme = getCookie(THEME_COOKIE_KEY);

  if (cookieTheme !== "light" && window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
      html.classList.add('color-theme-in-transition');
      window.setTimeout(() => {
        document.documentElement.classList.remove('color-theme-in-transition')
      }, 1000);
      setTheme("dark");
  }
  else {
      setTheme("light");
  }

  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
      html.classList.add('color-theme-in-transition');
      window.setTimeout(() => {
        document.documentElement.classList.remove('color-theme-in-transition')
      }, 1000);

      let theme = e.matches ? 'dark' : 'light';
      setTheme(theme);
      }
  );
};


const themeChanger = () => {

    const html = document.getElementsByTagName('html')[0];
    html.classList.add('color-theme-in-transition')

    const theme = html.getAttribute('data-theme');

    window.setTimeout(() => {
      document.documentElement.classList.remove('color-theme-in-transition')
    }, 1000);

    const newTheme = theme === 'dark' ? 'light' : 'dark';
    setTheme(newTheme);
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


const makeTablesSortable = () => {
  __("table").forEach(el => {
    el.classList.add("sortable");
  });
};

const onloadHandler = () => {
  _("#mode-switcher-input + div").onclick = themeChanger;
  activateColorSwitching();
  attachCheckboxes();
  addParentClasses();
  makeTablesSortable();
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
});
