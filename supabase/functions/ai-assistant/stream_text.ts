// Ағынды мәтінді клиентке жіберер алдындағы сүзгі: сөз ортасынан үзбейді және
// толық сөз (токен) болып келген сілтемелерді (http(s)://, www.) алып тастайды.
// Телефон нөмірі сияқты бірнеше сөзге созылатын үлгілерді ақырғы `done`
// хабарламасындағы stripLinks тазалайды (клиент соңында мәтінді сонымен ауыстырады).
export class DeltaFilter {
  private pending = "";

  /// Жаңа бөлікті береді; клиентке шығаруға болатын (аяқталған сөздер) бөлігін қайтарады.
  push(t: string): string {
    this.pending += t;
    // Соңғы бос орыннан кейінгі жартылай сөзді ұстап тұрамыз.
    const cut = Math.max(
      this.pending.lastIndexOf(" "),
      this.pending.lastIndexOf("\n"),
      this.pending.lastIndexOf("\t"),
    );
    if (cut < 0) return "";
    const ready = this.pending.slice(0, cut + 1);
    this.pending = this.pending.slice(cut + 1);
    return clean(ready);
  }

  /// Қалған жартылай сөзді шығарады.
  flush(): string {
    const r = clean(this.pending);
    this.pending = "";
    return r;
  }
}

function clean(s: string): string {
  return s.replace(/(?:https?:\/\/|www\.)\S+/gi, "");
}
