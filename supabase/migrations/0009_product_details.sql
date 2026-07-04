-- ── 0009: Тауар карточкасының қосымша өрістері ────────────────────────────────
-- description — тауар сипаттамасы (клиентке маркетплейс-стилде көрсетіледі)
-- country     — өндірілген елі
-- season      — сезондық: Лето|Зима|Осень|Весна ('' = көрсетілмеген)
-- Барлығы міндетті емес; ескі жолдар үшін default '' (fromMap та '' береді).

alter table public.products
  add column if not exists description text not null default '',
  add column if not exists country     text not null default '',
  add column if not exists season      text not null default '';
