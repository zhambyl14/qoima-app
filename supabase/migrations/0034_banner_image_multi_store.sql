-- Баннерге дайын дизайн-сурет (Cloudinary) және бірнеше дүкенге сілтеме
-- мүмкіндігін қосамыз. Ескі жалғыз store_admin_uid/store_name — жаңа
-- массивтерге көшіріліп, содан кейін алынып тасталады.

alter table public.banners
  add column if not exists image_url text not null default '',
  add column if not exists store_admin_uids uuid[] not null default '{}',
  add column if not exists store_names text[] not null default '{}';

update public.banners
  set store_admin_uids = array[store_admin_uid],
      store_names = array[coalesce(store_name, '')]
  where store_admin_uid is not null
    and store_admin_uids = '{}';

alter table public.banners
  drop column if exists store_admin_uid,
  drop column if exists store_name;
