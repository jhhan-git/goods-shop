-- 상품 사진: 이모지 대신 실물 사진(Unsplash License, images/products/)을 쓴다.
-- 디자인 금지 규칙(이모지·아이콘 금지)에 따라 emoji 칸은 삭제한다.

update public.products set image_url = 'images/products/mug.jpg'     where name = '로고 머그컵';
update public.products set image_url = 'images/products/sticker.jpg' where name = '스티커 팩';
update public.products set image_url = 'images/products/tote.jpg'    where name = '캔버스 에코백';
update public.products set image_url = 'images/products/keyring.jpg' where name = '아크릴 키링';
update public.products set image_url = 'images/products/hoodie.jpg'  where name = '오버핏 후드티';
update public.products set image_url = 'images/products/cap.jpg'     where name = '자수 볼캡';

alter table public.products drop column emoji;
