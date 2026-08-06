// Веб-те web/index.html-дегі window.qoimaMaps JS көпіріне типтелген
// сілтемелер. dart:js_interop (static interop) — dart:js_util ЖОЙЫЛҒАН
// (Dart 3.11-де URI табылмайды), сондықтан осы жаңа тәсіл қолданылады.
import 'dart:js_interop';

@JS('qoimaMaps.ready')
external JSPromise<JSBoolean> jsMapsReady();

@JS('qoimaMaps.init')
external JSBoolean jsMapsInit(
    JSString containerId, JSNumber lat, JSNumber lng, JSNumber zoom);

@JS('qoimaMaps.destroy')
external void jsMapsDestroy(JSString containerId);

@JS('qoimaMaps.setClickHandler')
external void jsMapsSetClickHandler(JSFunction? handler);

@JS('qoimaMaps.addPlacemark')
external void jsMapsAddPlacemark(
    JSString containerId, JSString id, JSNumber lat, JSNumber lng);

@JS('qoimaMaps.fitBounds')
external void jsMapsFitBounds(JSString containerId, JSArray<JSNumber> points);

@JS('qoimaMaps.initPicker')
external JSBoolean jsMapsInitPicker(JSString containerId, JSNumber lat,
    JSNumber lng, JSNumber zoom, JSBoolean hasInitial);

extension JSNumListExt on List<double> {
  JSArray<JSNumber> get toJSNumbers =>
      map((d) => d.toJS).toList().toJS;
}
