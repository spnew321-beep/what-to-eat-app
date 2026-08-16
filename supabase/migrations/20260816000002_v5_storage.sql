-- ============================================================================
-- 這餐吃什麼 App — Storage bucket for restaurant photos (v5)
-- ============================================================================
-- restaurant_photos.storage_path 指向這個 bucket 裡的檔案。
--
-- 設計:public bucket(getPublicUrl() 直接可讀,不用簽名網址,實作簡單、
-- 菜單照片不是敏感資料),但上傳/刪除限定本人——路徑第一層資料夾必須是
-- 自己的 auth.uid(),靠 storage.objects 的 RLS policy 擋住別人寫入/
-- 刪除你的資料夾。路徑慣例:{owner_user_id}/{restaurant_id}/{隨機檔名}
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('restaurant-photos', 'restaurant-photos', true)
on conflict (id) do nothing;

create policy "restaurant_photos_bucket_insert_own" on storage.objects for insert to authenticated
  with check (bucket_id = 'restaurant-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "restaurant_photos_bucket_update_own" on storage.objects for update to authenticated
  using (bucket_id = 'restaurant-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'restaurant-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "restaurant_photos_bucket_delete_own" on storage.objects for delete to authenticated
  using (bucket_id = 'restaurant-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "restaurant_photos_bucket_select_public" on storage.objects for select
  using (bucket_id = 'restaurant-photos');
