import 'dart:html' as html;

/// iOS/desktop Safari (әрі кейбір браузерлер) `window.open`-ді тек ТІКЕЛЕЙ
/// пайдаланушы әрекетінің синхронды жалғасында ашады — asynchronous RPC
/// (мыс. `await`) аяқталғаннан КЕЙІН шақырылса, попап-блокер оны үнсіз
/// бұғаттайды (қолданушыға ешбір қате көрінбейді, жай ештеңе ашылмайды).
///
/// Шешім: пайдаланушы басқан СӘТТЕ (RPC-тен БҰРЫН) бос терезе ашамыз да,
/// RPC жауабы келгенде сол терезенің `location`-ін нақты URL-ге бағыттаймыз
/// ([navigateWindowTo]). Бос терезе ашу — синхронды пайдаланушы әрекеті
/// ретінде саналады, сондықтан блокталмайды.
Object? openBlankWindow() => html.window.open('', '_blank');

void navigateWindowTo(Object? win, String url) {
  (win as html.WindowBase?)?.location.href = url;
}
