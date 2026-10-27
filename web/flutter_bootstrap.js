{{flutter_js}}
{{flutter_build_config}}

// The app is a phone screen, so it mounts in the #app frame (see
// index.html), which fills a phone and stays phone-sized on a wide window.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      hostElement: document.querySelector('#app'),
    });
    await appRunner.runApp();
  },
});
