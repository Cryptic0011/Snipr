/* Snipr landing animations. Content is fully visible without JS;
   GSAP only adds the entrance choreography. */

gsap.registerPlugin(ScrollTrigger);

const mm = gsap.matchMedia();

mm.add(
  {
    motionOK: "(prefers-reduced-motion: no-preference)",
    reduceMotion: "(prefers-reduced-motion: reduce)",
  },
  (context) => {
    const { reduceMotion } = context.conditions;
    if (reduceMotion) {
      // Static page: just fill in the real dimension readout.
      setDims();
      return;
    }

    heroIntro();
    scrollReveals();
  }
);

function setDims() {
  const box = document.getElementById("selbox");
  const dims = document.getElementById("seldims");
  dims.textContent = `${Math.round(box.offsetWidth)} × ${Math.round(box.offsetHeight)}`;
}

function heroIntro() {
  const box = document.getElementById("selbox");
  const dims = document.getElementById("seldims");
  const finalW = Math.round(box.offsetWidth);
  const finalH = Math.round(box.offsetHeight);
  const counter = { w: 0, h: 0 };

  const tl = gsap.timeline({ defaults: { ease: "power3.out", duration: 0.6 } });

  tl.from(".nav", { y: -14, autoAlpha: 0, duration: 0.45 })
    .from(".hero-copy .hero-el", { y: 22, autoAlpha: 0, stagger: 0.09 }, "-=0.15")
    .from(".hero-mock", { x: 28, autoAlpha: 0, duration: 0.7 }, "<0.2")
    // the capture: selection box draws itself around the headline
    .fromTo(
      box,
      { scaleX: 0.15, scaleY: 0.15, autoAlpha: 0, transformOrigin: "top left" },
      { scaleX: 1, scaleY: 1, autoAlpha: 1, duration: 0.5, ease: "power2.inOut" },
      "-=0.4"
    )
    .to(
      counter,
      {
        w: finalW,
        h: finalH,
        duration: 0.5,
        ease: "power2.inOut",
        snap: { w: 1, h: 1 },
        onUpdate: () => (dims.textContent = `${counter.w} × ${counter.h}`),
      },
      "<"
    )
    .from(
      "#selbox .h",
      { scale: 0, duration: 0.3, ease: "back.out(2.5)", stagger: { each: 0.03, from: "edges" } },
      "-=0.2"
    )
    // shutter
    .fromTo("#flash", { autoAlpha: 0 }, { autoAlpha: 0.5, duration: 0.07, ease: "none" }, "+=0.15")
    .to("#flash", { autoAlpha: 0, duration: 0.25, ease: "power1.out" });
}

function scrollReveals() {
  document.querySelectorAll("[data-reveal]").forEach((el) => {
    gsap.from(el, {
      y: 24,
      autoAlpha: 0,
      duration: 0.7,
      ease: "power2.out",
      scrollTrigger: { trigger: el, start: "top 85%", once: true },
    });
  });

  document.querySelectorAll("[data-reveal-group]").forEach((group) => {
    gsap.from(group.children, {
      y: 24,
      autoAlpha: 0,
      duration: 0.6,
      ease: "power2.out",
      stagger: 0.08,
      scrollTrigger: { trigger: group, start: "top 85%", once: true },
    });
  });
}

/* Point the download buttons at the latest DMG and show its version.
   Falls back to the releases page if the API is unreachable. */
fetch("https://api.github.com/repos/Cryptic0011/Snipr/releases/latest")
  .then((r) => (r.ok ? r.json() : null))
  .then((release) => {
    if (!release) return;
    const dmg = (release.assets || []).find((a) => a.name.endsWith(".dmg"));
    if (dmg) {
      for (const id of ["download-btn", "download-btn-2"]) {
        document.getElementById(id).href = dmg.browser_download_url;
      }
    }
    const label = document.getElementById("version-label");
    if (release.tag_name) label.textContent = release.tag_name;
  })
  .catch(() => {});
