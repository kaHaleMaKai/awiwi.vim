const _ = (expr) => {
  if (typeof expr === "string") {
    return document.querySelector(expr);
  }
  return expr;
}

const except = (array, expr) => {
}

const asCustomArray = (...arr) => {
  const ret = [...arr];
  ret.except = (expr) => asCustomArray(...ret.filter(el => el !== expr));
  ret.addClasses = (...classes) => {
    ret.forEach(el => el.classList.add(...classes))
    return ret;
  };
  ret.removeClasses = (...classes) => {
    ret.forEach(el => el.classList.remove(...classes));
    return ret;
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

const createNode = (expr) => {
  if (typeof expr === 'object') {
    return expr;
  }
  const splits = expr.split('.');
  const nodeType = splits[0];
  const container = document.createElement(nodeType);
  if (splits.length > 1) {
    asCustomArray(splits.slice(1)).forEach(className => container.classList.add(className));
  }
  return container;
}

const wrap = (el, wrapper) => {
  const node = _(el);
  const container = createNode(wrapper);
  node.parentNode.insertBefore(container, node);
  container.appendChild(node);
  return container;
}

const wrapChildren = (el, wrapper) => {
  const node = _(el);
  const container = createNode(wrapper);
  node.insertBefore(container, node.firstElementChild);
  let sib = container.nextElementSibling;
  while (sib !== null) {
    container.appendChild(sib);
    sib = container.nextElementSibling;
  }
  node.appendChild(container);
  return container;
}

let sectionIndex = [];

const wrapInSection = (start) => {
  const cls = start.tagName === "H2" ? "page" : "subpage";
  const nodeExpr = `section.${cls}`;
  const section = createNode(nodeExpr);
  const nodes = [];
  nodes.push(start);
  let sib = start.nextElementSibling;
  while (sib !== null) {
    if (/^H[23]$/.test(sib.tagName)) {
      break;
    }
    nodes.push(sib);
    sib = sib.nextElementSibling;
  }
  start.parentNode.insertBefore(section, start);
  nodes.forEach(n => section.appendChild(n));
  return section;
}

const wrapInSections = () => {
  if (_("section") !== null) {
    return;
  }
    __("div.article > h2, div.article > h3").forEach(h => wrapInSection(h));
  const index = [];
  let numPages = 0;
  __("section.page").forEach(s => {
    s.id = `section-${numPages}_0`;
    s.setAttribute("data-page", numPages);
    s.setAttribute("data-sub-page", 0);
    const subIndex = [s];
    let numSubPages = 1;

    let sib = s.nextElementSibling;
    while (sib !== null) {
      if (sib.classList.contains("page")) {
        break;
      }
      else if (sib.classList.contains("subpage")) {
        sib.id = `section-${numPages}_${numSubPages}`;
        sib.setAttribute("data-page", numPages);
        sib.setAttribute("data-sub-page", numSubPages);
        numSubPages++;
        subIndex.push(sib);
      }
      sib = sib.nextElementSibling;
    }

    numPages++;
    index.push(subIndex);
  })
  sectionIndex = index;
}

const hideSurrounding = () => {
  __("body", "html", "div.container").addClasses("no-overflow");
  __("div.aside",
    "div.top-bar",
    "#footer-separator",
    "div.prevnext.large"
  ).addClasses("hidden");
  _("div.article").classList.add("modal");
}

const unhideSurrounding = () => {
  __("div.aside",
    "div.top-bar",
    "#footer-separator",
    "div.prevnext.large"
  ).removeClasses("hidden");
  __("body", "html", "div.container").removeClasses("no-overflow");
  _("div.article").classList.remove("modal");
}

const prepareSlides = () => {
  _("#section-0_0").classList.add("current-page");
}

let isPresenting = false;

const togglePresentation = () => {
  wrapInSections();
  if (isPresenting) {
    unhideSurrounding();
    _("section.current-page").classList.remove("current-page");
    __("section").removeClasses(
      "fade-left", "fade-right", "fade-up", "fade-down", "hidden",
      "presenting", "current-page"
    );
  }
  else {
    hideSurrounding();
    _("section").classList.add("current-page");

    __("section")
      .addClasses("presenting")
      .except(_("section.current-page"))
      .addClasses("hidden");
    __("section.page").except(_("section.current-page")).addClasses("fade-right");
    __("section.subpage").addClasses("fade-down");
  }
  isPresenting = !isPresenting;
}

const getPageNumber = (el) => {
  return Number(el.getAttribute("data-page"));
}

const getSubPageNumber = (el) => {
  return Number(el.getAttribute("data-sub-page"));
}

const getNextPage = (direction) => {
  const page = getPageNumber(_("section.current-page"));
  const subPage = getSubPageNumber(_("section.current-page"));
  if (page > 0 && direction === "left") {
    return sectionIndex[page-1][0];
  }
  else if (page < sectionIndex.length - 1 && direction === "right") {
    return sectionIndex[page+1][0];
  }
  else if (subPage > 0 && direction === "up") {
    return sectionIndex[page][subPage-1];
  }
  else if (subPage < sectionIndex[page].length - 1 && direction === "down") {
    return sectionIndex[page][subPage+1];
  }
  return null;
}

const getOppositeDirection = (direction) => {
  switch (direction) {
    case "left": return "right";
    case "right": return "left";
    case "up": return "down";
    case "down": return "up";
  }
}

const removeFadeClasses = (el) => {
  el.classList.forEach(cls => {
    if (cls.startsWith("fade-")) {
      el.classList.remove(cls);
    }
  });
}

const replaceFadeClass = (el, cls) => {
  removeFadeClasses(el);
  el.classList.add(cls);
}

const makeSlideVisible = (el) => {
  removeFadeClasses(el);
  el.classList.remove("hidden");
}

const fadePage = (direction) => {
  const nextPage = getNextPage(direction);
  if (nextPage === null) {
    return;
  }
  const currentPage = _("section.current-page");
  currentPage.classList.remove("current-page")
  const cls = "fade-" + getOppositeDirection(direction);
  currentPage.classList.add(cls, "hidden");
  nextPage.classList.add("current-page");

  const pageNr = getPageNumber(currentPage);
  const subPageNr = getSubPageNumber(currentPage);
  const nextPageNr = getPageNumber(nextPage);
  const nextSubPageNr = getSubPageNumber(nextPage);

  if (pageNr < nextPageNr) {
    if (subPageNr > 0) {
      replaceFadeClass(_(`#section-${pageNr}_0`), "fade-left");
    }
    __(`section.hidden.subpage[data-page='${nextPageNr}']`).forEach(el => replaceFadeClass(el, "fade-down"));
  }
  if (pageNr > nextPageNr) {
    if (subPageNr > 0) {
      replaceFadeClass(_(`#section-${pageNr}_0`), "fade-right");
    }
    __(`section.hidden.subpage[data-page='${nextPageNr}']`).forEach(el => replaceFadeClass(el, "fade-down"));
  }

  makeSlideVisible(nextPage)
}

document.addEventListener('keyup', (e) => {
  if (e.code === "KeyF") {
    togglePresentation();
    return;
  }
  if (!isPresenting) return;

  if (e.code === "ArrowLeft" || e.code === "ArrowRight"
      || e.code === "ArrowUp" || e.code === "ArrowDown") {
    const direction = e.code.substring(5).toLowerCase();
    fadePage(direction);
  }

})
