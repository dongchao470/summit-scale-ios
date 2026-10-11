// 复现实验：大块字典字面量在运行库上是否会 trap。
//
// 背景：0.3.4 build 7 与 0.3.5 build 8 两次真机崩溃，栈帧都是
//   FoodItem.<图字段>.getter
//   -> one-time initialization function for map
//   -> dictionaryLiteral  -> EXC_BREAKPOINT / SIGTRAP
// 源码里 434 个 key 零重复，所以怀疑是「字面量构造」这条路本身在
// 大元素量下不可靠。这个程序把两种写法都跑一遍，谁炸谁活一目了然。
//
// 用 swift 直接跑（脚本模式），CI 与本地都能验证。

import Foundation

// 写法 A：434 项字典字面量（0.3.5 build 8 的写法）
let literalMap: [String: String] = [
    "almond": "https://example.invalid/almond.jpg",
    "americano": "https://example.invalid/americano.jpg",
    "ants_tree": "https://example.invalid/ants_tree.jpg",
    "apple": "https://example.invalid/apple.jpg",
    "asparagus": "https://example.invalid/asparagus.jpg",
    "avocado": "https://example.invalid/avocado.jpg",
    "baby_cabbage": "https://example.invalid/baby_cabbage.jpg",
    "bacon": "https://example.invalid/bacon.jpg",
    "baijiu": "https://example.invalid/baijiu.jpg",
    "banana": "https://example.invalid/banana.jpg",
    "baozi": "https://example.invalid/baozi.jpg",
    "bass": "https://example.invalid/bass.jpg",
    "beef_jerky": "https://example.invalid/beef_jerky.jpg",
    "beef_lean": "https://example.invalid/beef_lean.jpg",
    "beef_noodle": "https://example.invalid/beef_noodle.jpg",
    "beef_roll": "https://example.invalid/beef_roll.jpg",
    "beer": "https://example.invalid/beer.jpg",
    "bibimbap": "https://example.invalid/bibimbap.jpg",
    "bitter_melon": "https://example.invalid/bitter_melon.jpg",
    "blueberry": "https://example.invalid/blueberry.jpg",
    "boiled_chicken": "https://example.invalid/boiled_chicken.jpg",
    "boiled_pork_slices": "https://example.invalid/boiled_pork_slices.jpg",
    "borscht": "https://example.invalid/borscht.jpg",
    "braised_chicken_rice": "https://example.invalid/braised_chicken_rice.jpg",
    "braised_eggplant": "https://example.invalid/braised_eggplant.jpg",
    "braised_hairtail": "https://example.invalid/braised_hairtail.jpg",
    "braised_pork": "https://example.invalid/braised_pork.jpg",
    "braised_ribs": "https://example.invalid/braised_ribs.jpg",
    "bread_toast": "https://example.invalid/bread_toast.jpg",
    "bread_whole": "https://example.invalid/bread_whole.jpg",
    "brisket": "https://example.invalid/brisket.jpg",
    "broccoli": "https://example.invalid/broccoli.jpg",
    "burger": "https://example.invalid/burger.jpg",
    "butter": "https://example.invalid/butter.jpg",
    "cabbage": "https://example.invalid/cabbage.jpg",
    "carrot": "https://example.invalid/carrot.jpg",
    "cashew": "https://example.invalid/cashew.jpg",
    "celery_pork": "https://example.invalid/celery_pork.jpg",
    "century_egg_congee": "https://example.invalid/century_egg_congee.jpg",
    "cf_americano": "https://example.invalid/cf_americano.jpg",
    "cf_cappuccino": "https://example.invalid/cf_cappuccino.jpg",
    "cf_caramel_macchiato": "https://example.invalid/cf_caramel_macchiato.jpg",
    "cf_cheese_foam_tea": "https://example.invalid/cf_cheese_foam_tea.jpg",
    "cf_coconut_latte": "https://example.invalid/cf_coconut_latte.jpg",
    "cf_fruit_tea": "https://example.invalid/cf_fruit_tea.jpg",
    "cf_hot_cocoa": "https://example.invalid/cf_hot_cocoa.jpg",
    "cf_latte": "https://example.invalid/cf_latte.jpg",
    "cf_lemon_tea": "https://example.invalid/cf_lemon_tea.jpg",
    "cf_mango_pomelo": "https://example.invalid/cf_mango_pomelo.jpg",
    "cf_matcha_latte": "https://example.invalid/cf_matcha_latte.jpg",
    "cf_milk_coffee": "https://example.invalid/cf_milk_coffee.jpg",
    "cf_milk_tea": "https://example.invalid/cf_milk_tea.jpg",
    "cf_mocha": "https://example.invalid/cf_mocha.jpg",
    "cf_oat_latte": "https://example.invalid/cf_oat_latte.jpg",
    "cf_taro_boba": "https://example.invalid/cf_taro_boba.jpg",
    "changfen": "https://example.invalid/changfen.jpg",
    "cheese": "https://example.invalid/cheese.jpg",
    "cherry": "https://example.invalid/cherry.jpg",
    "cherry_tomato": "https://example.invalid/cherry_tomato.jpg",
    "chicken_breast": "https://example.invalid/chicken_breast.jpg",
    "chicken_leg": "https://example.invalid/chicken_leg.jpg",
    "chicken_nugget": "https://example.invalid/chicken_nugget.jpg",
    "chicken_pot": "https://example.invalid/chicken_pot.jpg",
    "chicken_soup": "https://example.invalid/chicken_soup.jpg",
    "chicken_wing": "https://example.invalid/chicken_wing.jpg",
    "chips": "https://example.invalid/chips.jpg",
    "clam": "https://example.invalid/clam.jpg",
    "cola": "https://example.invalid/cola.jpg",
    "cola_wings": "https://example.invalid/cola_wings.jpg",
    "cola_zero": "https://example.invalid/cola_zero.jpg",
    "cold_cucumber": "https://example.invalid/cold_cucumber.jpg",
    "cold_fungus": "https://example.invalid/cold_fungus.jpg",
    "congee": "https://example.invalid/congee.jpg",
    "corn": "https://example.invalid/corn.jpg",
    "corn_ribs": "https://example.invalid/corn_ribs.jpg",
    "crab": "https://example.invalid/crab.jpg",
    "cream_cake": "https://example.invalid/cream_cake.jpg",
    "curry_chicken": "https://example.invalid/curry_chicken.jpg",
    "curry_rice": "https://example.invalid/curry_rice.jpg",
    "d2_americano_iced": "https://example.invalid/d2_americano_iced.jpg",
    "d2_beef_ball_soup": "https://example.invalid/d2_beef_ball_soup.jpg",
    "d2_beef_chow_fun": "https://example.invalid/d2_beef_chow_fun.jpg",
    "d2_beef_rice": "https://example.invalid/d2_beef_rice.jpg",
    "d2_beef_tendon": "https://example.invalid/d2_beef_tendon.jpg",
    "d2_big_plate_chicken": "https://example.invalid/d2_big_plate_chicken.jpg",
    "d2_black_bean": "https://example.invalid/d2_black_bean.jpg",
    "d2_blanched_shrimp": "https://example.invalid/d2_blanched_shrimp.jpg",
    "d2_braised_noodles_bean": "https://example.invalid/d2_braised_noodles_bean.jpg",
    "d2_braised_pork_rice": "https://example.invalid/d2_braised_pork_rice.jpg",
    "d2_braised_sea_cucumber": "https://example.invalid/d2_braised_sea_cucumber.jpg",
    "d2_brown_sugar_milk_tea": "https://example.invalid/d2_brown_sugar_milk_tea.jpg",
    "d2_butter_cookie": "https://example.invalid/d2_butter_cookie.jpg",
    "d2_caesar_salad": "https://example.invalid/d2_caesar_salad.jpg",
    "d2_cauliflower": "https://example.invalid/d2_cauliflower.jpg",
    "d2_celery": "https://example.invalid/d2_celery.jpg",
    "d2_char_siu": "https://example.invalid/d2_char_siu.jpg",
    "d2_cheese_grape_tea": "https://example.invalid/d2_cheese_grape_tea.jpg",
    "d2_cheese_slice": "https://example.invalid/d2_cheese_slice.jpg",
    "d2_cheese_stick": "https://example.invalid/d2_cheese_stick.jpg",
    "d2_chestnut": "https://example.invalid/d2_chestnut.jpg",
    "d2_chicken_feet": "https://example.invalid/d2_chicken_feet.jpg",
    "d2_chicken_popcorn": "https://example.invalid/d2_chicken_popcorn.jpg",
    "d2_chicken_salad": "https://example.invalid/d2_chicken_salad.jpg",
    "d2_chicken_wrap": "https://example.invalid/d2_chicken_wrap.jpg",
    "d2_chickpea": "https://example.invalid/d2_chickpea.jpg",
    "d2_chili_oil": "https://example.invalid/d2_chili_oil.jpg",
    "d2_chocolate_milk": "https://example.invalid/d2_chocolate_milk.jpg",
    "d2_chopped_pepper_fish_head": "https://example.invalid/d2_chopped_pepper_fish_head.jpg",
    "d2_claypot_rice": "https://example.invalid/d2_claypot_rice.jpg",
    "d2_coconut_meat": "https://example.invalid/d2_coconut_meat.jpg",
    "d2_coconut_water": "https://example.invalid/d2_coconut_water.jpg",
    "d2_condensed_milk": "https://example.invalid/d2_condensed_milk.jpg",
    "d2_cookie_chocolate": "https://example.invalid/d2_cookie_chocolate.jpg",
    "d2_cream": "https://example.invalid/d2_cream.jpg",
    "d2_dongpo_pork": "https://example.invalid/d2_dongpo_pork.jpg",
    "d2_double_burger": "https://example.invalid/d2_double_burger.jpg",
    "d2_dried_beancurd_snack": "https://example.invalid/d2_dried_beancurd_snack.jpg",
    "d2_durian": "https://example.invalid/d2_durian.jpg",
    "d2_edamame": "https://example.invalid/d2_edamame.jpg",
    "d2_egg_pancake": "https://example.invalid/d2_egg_pancake.jpg",
    "d2_egg_roll": "https://example.invalid/d2_egg_roll.jpg",
    "d2_fish_fragrant_eggplant": "https://example.invalid/d2_fish_fragrant_eggplant.jpg",
    "d2_fish_tofu": "https://example.invalid/d2_fish_tofu.jpg",
    "d2_flat_white": "https://example.invalid/d2_flat_white.jpg",
    "d2_fresh_soy_milk": "https://example.invalid/d2_fresh_soy_milk.jpg",
    "d2_fried_chicken_thigh": "https://example.invalid/d2_fried_chicken_thigh.jpg",
    "d2_fried_chicken_wing": "https://example.invalid/d2_fried_chicken_wing.jpg",
    "d2_fujian_wonton": "https://example.invalid/d2_fujian_wonton.jpg",
    "d2_geda_soup": "https://example.invalid/d2_geda_soup.jpg",
    "d2_glutinous_cake": "https://example.invalid/d2_glutinous_cake.jpg",
    "d2_glutinous_rice_roll": "https://example.invalid/d2_glutinous_rice_roll.jpg",
    "d2_goose_meat": "https://example.invalid/d2_goose_meat.jpg",
    "d2_grape_purple": "https://example.invalid/d2_grape_purple.jpg",
    "d2_guilin_rice_noodle": "https://example.invalid/d2_guilin_rice_noodle.jpg",
    "d2_gummy": "https://example.invalid/d2_gummy.jpg",
    "d2_guobaorou": "https://example.invalid/d2_guobaorou.jpg",
    "d2_hand_grabbed_lamb": "https://example.invalid/d2_hand_grabbed_lamb.jpg",
    "d2_hazelnut": "https://example.invalid/d2_hazelnut.jpg",
    "d2_hot_dry_noodles": "https://example.invalid/d2_hot_dry_noodles.jpg",
    "d2_hotdog": "https://example.invalid/d2_hotdog.jpg",
    "d2_hp_crispy_pork": "https://example.invalid/d2_hp_crispy_pork.jpg",
    "d2_hp_duck_blood": "https://example.invalid/d2_hp_duck_blood.jpg",
    "d2_hp_thousand_tripe": "https://example.invalid/d2_hp_thousand_tripe.jpg",
    "d2_hulatang": "https://example.invalid/d2_hulatang.jpg",
    "d2_ice_cream_cone": "https://example.invalid/d2_ice_cream_cone.jpg",
    "d2_konjac_snack": "https://example.invalid/d2_konjac_snack.jpg",
    "d2_lamb_chop": "https://example.invalid/d2_lamb_chop.jpg",
    "d2_lanzhou_noodles": "https://example.invalid/d2_lanzhou_noodles.jpg",
    "d2_liangfen": "https://example.invalid/d2_liangfen.jpg",
    "d2_loofah": "https://example.invalid/d2_loofah.jpg",
    "d2_mapo_rice": "https://example.invalid/d2_mapo_rice.jpg",
    "d2_marshmallow": "https://example.invalid/d2_marshmallow.jpg",
    "d2_milk_candy": "https://example.invalid/d2_milk_candy.jpg",
    "d2_milk_oatmeal": "https://example.invalid/d2_milk_oatmeal.jpg",
    "d2_northeast_stew": "https://example.invalid/d2_northeast_stew.jpg",
    "d2_onion_ring": "https://example.invalid/d2_onion_ring.jpg",
    "d2_oolong_tea": "https://example.invalid/d2_oolong_tea.jpg",
    "d2_papaya": "https://example.invalid/d2_papaya.jpg",
    "d2_pea_shoot": "https://example.invalid/d2_pea_shoot.jpg",
    "d2_pear_juice": "https://example.invalid/d2_pear_juice.jpg",
    "d2_pepper_pork_liver": "https://example.invalid/d2_pepper_pork_liver.jpg",
    "d2_persimmon": "https://example.invalid/d2_persimmon.jpg",
    "d2_pigeon": "https://example.invalid/d2_pigeon.jpg",
    "d2_pine_nut": "https://example.invalid/d2_pine_nut.jpg",
    "d2_plum": "https://example.invalid/d2_plum.jpg",
    "d2_popsicle_fruit": "https://example.invalid/d2_popsicle_fruit.jpg",
    "d2_pork_bun": "https://example.invalid/d2_pork_bun.jpg",
    "d2_pork_chop_rice": "https://example.invalid/d2_pork_chop_rice.jpg",
    "d2_pork_ear": "https://example.invalid/d2_pork_ear.jpg",
    "d2_pork_heart": "https://example.invalid/d2_pork_heart.jpg",
    "d2_pork_jerky": "https://example.invalid/d2_pork_jerky.jpg",
    "d2_pork_liver": "https://example.invalid/d2_pork_liver.jpg",
    "d2_potato_salad": "https://example.invalid/d2_potato_salad.jpg",
    "d2_potato_stew_beef": "https://example.invalid/d2_potato_stew_beef.jpg",
    "d2_potato_vermicelli": "https://example.invalid/d2_potato_vermicelli.jpg",
    "d2_pumpkin_bun": "https://example.invalid/d2_pumpkin_bun.jpg",
    "d2_quail_egg": "https://example.invalid/d2_quail_egg.jpg",
    "d2_radish_rib_soup": "https://example.invalid/d2_radish_rib_soup.jpg",
    "d2_rice_ball": "https://example.invalid/d2_rice_ball.jpg",
    "d2_rice_cake_soup": "https://example.invalid/d2_rice_cake_soup.jpg",
    "d2_rice_cracker": "https://example.invalid/d2_rice_cracker.jpg",
    "d2_roast_duck": "https://example.invalid/d2_roast_duck.jpg",
    "d2_salt_baked_chicken": "https://example.invalid/d2_salt_baked_chicken.jpg",
    "d2_salted_duck": "https://example.invalid/d2_salted_duck.jpg",
    "d2_salted_milk_tea": "https://example.invalid/d2_salted_milk_tea.jpg",
    "d2_sandwich_egg": "https://example.invalid/d2_sandwich_egg.jpg",
    "d2_sauerkraut_fish": "https://example.invalid/d2_sauerkraut_fish.jpg",
    "d2_scallion_oil_noodles": "https://example.invalid/d2_scallion_oil_noodles.jpg",
    "d2_seaweed_cracker": "https://example.invalid/d2_seaweed_cracker.jpg",
    "d2_seaweed_egg_soup": "https://example.invalid/d2_seaweed_egg_soup.jpg",
    "d2_seaweed_roll": "https://example.invalid/d2_seaweed_roll.jpg",
    "d2_sesame_ball": "https://example.invalid/d2_sesame_ball.jpg",
    "d2_shaxian_noodles": "https://example.invalid/d2_shaxian_noodles.jpg",
    "d2_shrimp_cracker": "https://example.invalid/d2_shrimp_cracker.jpg",
    "d2_shuizhu_beef": "https://example.invalid/d2_shuizhu_beef.jpg",
    "d2_soda_cracker_cream": "https://example.invalid/d2_soda_cracker_cream.jpg",
    "d2_soybean_trotter": "https://example.invalid/d2_soybean_trotter.jpg",
    "d2_sparkling_water": "https://example.invalid/d2_sparkling_water.jpg",
    "d2_spicy_chicken_burger": "https://example.invalid/d2_spicy_chicken_burger.jpg",
    "d2_spicy_crayfish": "https://example.invalid/d2_spicy_crayfish.jpg",
    "d2_sports_water": "https://example.invalid/d2_sports_water.jpg",
    "d2_sprite": "https://example.invalid/d2_sprite.jpg",
    "d2_steamed_roll": "https://example.invalid/d2_steamed_roll.jpg",
    "d2_stinky_tofu": "https://example.invalid/d2_stinky_tofu.jpg",
    "d2_suan_cai_pork": "https://example.invalid/d2_suan_cai_pork.jpg",
    "d2_sweet_sour_fish": "https://example.invalid/d2_sweet_sour_fish.jpg",
    "d2_swiss_roll": "https://example.invalid/d2_swiss_roll.jpg",
    "d2_tea_egg": "https://example.invalid/d2_tea_egg.jpg",
    "d2_tofu_pudding": "https://example.invalid/d2_tofu_pudding.jpg",
    "d2_tofu_skin_sheet": "https://example.invalid/d2_tofu_skin_sheet.jpg",
    "d2_tomato_egg_rice": "https://example.invalid/d2_tomato_egg_rice.jpg",
    "d2_veggie_bun": "https://example.invalid/d2_veggie_bun.jpg",
    "d2_wafer": "https://example.invalid/d2_wafer.jpg",
    "d2_westlake_fish": "https://example.invalid/d2_westlake_fish.jpg",
    "d2_wheat_noodle_soup": "https://example.invalid/d2_wheat_noodle_soup.jpg",
    "d2_whole_milk_powder": "https://example.invalid/d2_whole_milk_powder.jpg",
    "d2_wonton": "https://example.invalid/d2_wonton.jpg",
    "d2_wonton_noodles": "https://example.invalid/d2_wonton_noodles.jpg",
    "d2_xianggu_rice": "https://example.invalid/d2_xianggu_rice.jpg",
    "d2_yam_rib_soup": "https://example.invalid/d2_yam_rib_soup.jpg",
    "d2_yanduxian": "https://example.invalid/d2_yanduxian.jpg",
    "d2_yangrou_paomo": "https://example.invalid/d2_yangrou_paomo.jpg",
    "d2_youmian_kao": "https://example.invalid/d2_youmian_kao.jpg",
    "d2_zhajiang_noodles": "https://example.invalid/d2_zhajiang_noodles.jpg",
    "dark_chocolate": "https://example.invalid/dark_chocolate.jpg",
    "disanxian": "https://example.invalid/disanxian.jpg",
    "donut": "https://example.invalid/donut.jpg",
    "doubanjiang": "https://example.invalid/doubanjiang.jpg",
    "dragon_fruit": "https://example.invalid/dragon_fruit.jpg",
    "dried_tofu": "https://example.invalid/dried_tofu.jpg",
    "dry_beans": "https://example.invalid/dry_beans.jpg",
    "dry_cauliflower": "https://example.invalid/dry_cauliflower.jpg",
    "dry_four_season": "https://example.invalid/dry_four_season.jpg",
    "duck": "https://example.invalid/duck.jpg",
    "duck_breast": "https://example.invalid/duck_breast.jpg",
    "dumpling": "https://example.invalid/dumpling.jpg",
    "egg_boiled": "https://example.invalid/egg_boiled.jpg",
    "egg_fried": "https://example.invalid/egg_fried.jpg",
    "egg_fried_rice": "https://example.invalid/egg_fried_rice.jpg",
    "egg_tart": "https://example.invalid/egg_tart.jpg",
    "egg_white": "https://example.invalid/egg_white.jpg",
    "eggplant": "https://example.invalid/eggplant.jpg",
    "eight_treasure": "https://example.invalid/eight_treasure.jpg",
    "enoki": "https://example.invalid/enoki.jpg",
    "fried_chicken": "https://example.invalid/fried_chicken.jpg",
    "fried_dumpling": "https://example.invalid/fried_dumpling.jpg",
    "fried_noodles": "https://example.invalid/fried_noodles.jpg",
    "fried_peanuts": "https://example.invalid/fried_peanuts.jpg",
    "fried_rice": "https://example.invalid/fried_rice.jpg",
    "fried_rice_noodle": "https://example.invalid/fried_rice_noodle.jpg",
    "fries": "https://example.invalid/fries.jpg",
    "fungus": "https://example.invalid/fungus.jpg",
    "fuzhu": "https://example.invalid/fuzhu.jpg",
    "garlic_broccoli": "https://example.invalid/garlic_broccoli.jpg",
    "garlic_pork": "https://example.invalid/garlic_pork.jpg",
    "garlic_sprout_pork": "https://example.invalid/garlic_sprout_pork.jpg",
    "glutinous_rice": "https://example.invalid/glutinous_rice.jpg",
    "grape": "https://example.invalid/grape.jpg",
    "green_pepper": "https://example.invalid/green_pepper.jpg",
    "guamian": "https://example.invalid/guamian.jpg",
    "guotie": "https://example.invalid/guotie.jpg",
    "hairtail": "https://example.invalid/hairtail.jpg",
    "ham_sausage": "https://example.invalid/ham_sausage.jpg",
    "hami_melon": "https://example.invalid/hami_melon.jpg",
    "hand_cabbage": "https://example.invalid/hand_cabbage.jpg",
    "hand_pancake": "https://example.invalid/hand_pancake.jpg",
    "hefen": "https://example.invalid/hefen.jpg",
    "honey": "https://example.invalid/honey.jpg",
    "hot_sour_noodles": "https://example.invalid/hot_sour_noodles.jpg",
    "hp_beef_ball": "https://example.invalid/hp_beef_ball.jpg",
    "hp_beef_omasum": "https://example.invalid/hp_beef_omasum.jpg",
    "hp_beef_slice": "https://example.invalid/hp_beef_slice.jpg",
    "hp_beef_tripe": "https://example.invalid/hp_beef_tripe.jpg",
    "hp_broad_vermicelli": "https://example.invalid/hp_broad_vermicelli.jpg",
    "hp_broth_mushroom": "https://example.invalid/hp_broth_mushroom.jpg",
    "hp_broth_tomato": "https://example.invalid/hp_broth_tomato.jpg",
    "hp_crab_stick": "https://example.invalid/hp_crab_stick.jpg",
    "hp_duck_intestine": "https://example.invalid/hp_duck_intestine.jpg",
    "hp_egg_dumpling": "https://example.invalid/hp_egg_dumpling.jpg",
    "hp_fish_ball": "https://example.invalid/hp_fish_ball.jpg",
    "hp_lamb_roll": "https://example.invalid/hp_lamb_roll.jpg",
    "hp_lotus_root_slice": "https://example.invalid/hp_lotus_root_slice.jpg",
    "hp_potato_slice": "https://example.invalid/hp_potato_slice.jpg",
    "hp_sesame_dip": "https://example.invalid/hp_sesame_dip.jpg",
    "hp_sesame_oil_dip": "https://example.invalid/hp_sesame_oil_dip.jpg",
    "hp_shrimp_dumpling": "https://example.invalid/hp_shrimp_dumpling.jpg",
    "hp_shrimp_paste": "https://example.invalid/hp_shrimp_paste.jpg",
    "hp_sweet_potato_noodle": "https://example.invalid/hp_sweet_potato_noodle.jpg",
    "hp_tofu_skin": "https://example.invalid/hp_tofu_skin.jpg",
    "hp_winter_melon_slice": "https://example.invalid/hp_winter_melon_slice.jpg",
    "ice_bar": "https://example.invalid/ice_bar.jpg",
    "ice_cream": "https://example.invalid/ice_cream.jpg",
    "instant_noodle": "https://example.invalid/instant_noodle.jpg",
    "jelly": "https://example.invalid/jelly.jpg",
    "jianbing": "https://example.invalid/jianbing.jpg",
    "kelp": "https://example.invalid/kelp.jpg",
    "ketchup": "https://example.invalid/ketchup.jpg",
    "kiwi": "https://example.invalid/kiwi.jpg",
    "kumquat": "https://example.invalid/kumquat.jpg",
    "kungpao_chicken": "https://example.invalid/kungpao_chicken.jpg",
    "lamb_lean": "https://example.invalid/lamb_lean.jpg",
    "lard": "https://example.invalid/lard.jpg",
    "latiao": "https://example.invalid/latiao.jpg",
    "leek": "https://example.invalid/leek.jpg",
    "leek_egg": "https://example.invalid/leek_egg.jpg",
    "lemon": "https://example.invalid/lemon.jpg",
    "lettuce": "https://example.invalid/lettuce.jpg",
    "liangpi": "https://example.invalid/liangpi.jpg",
    "lianou_fen": "https://example.invalid/lianou_fen.jpg",
    "lotus_root": "https://example.invalid/lotus_root.jpg",
    "luncheon_meat": "https://example.invalid/luncheon_meat.jpg",
    "luosifen": "https://example.invalid/luosifen.jpg",
    "lychee": "https://example.invalid/lychee.jpg",
    "malatang": "https://example.invalid/malatang.jpg",
    "mango": "https://example.invalid/mango.jpg",
    "mantou": "https://example.invalid/mantou.jpg",
    "maocai": "https://example.invalid/maocai.jpg",
    "maoxuewang": "https://example.invalid/maoxuewang.jpg",
    "mapo_tofu": "https://example.invalid/mapo_tofu.jpg",
    "marinated_egg": "https://example.invalid/marinated_egg.jpg",
    "mayonnaise": "https://example.invalid/mayonnaise.jpg",
    "milk_skim": "https://example.invalid/milk_skim.jpg",
    "milk_tea": "https://example.invalid/milk_tea.jpg",
    "milk_whole": "https://example.invalid/milk_whole.jpg",
    "millet_congee": "https://example.invalid/millet_congee.jpg",
    "mixian": "https://example.invalid/mixian.jpg",
    "mung_bean": "https://example.invalid/mung_bean.jpg",
    "mung_soup": "https://example.invalid/mung_soup.jpg",
    "mung_sprout": "https://example.invalid/mung_sprout.jpg",
    "mushroom_chicken": "https://example.invalid/mushroom_chicken.jpg",
    "niangao": "https://example.invalid/niangao.jpg",
    "noodles": "https://example.invalid/noodles.jpg",
    "oats": "https://example.invalid/oats.jpg",
    "oden": "https://example.invalid/oden.jpg",
    "okra": "https://example.invalid/okra.jpg",
    "omurice": "https://example.invalid/omurice.jpg",
    "onion": "https://example.invalid/onion.jpg",
    "orange": "https://example.invalid/orange.jpg",
    "orange_juice": "https://example.invalid/orange_juice.jpg",
    "oreo": "https://example.invalid/oreo.jpg",
    "oyster_sauce": "https://example.invalid/oyster_sauce.jpg",
    "pasta": "https://example.invalid/pasta.jpg",
    "peach": "https://example.invalid/peach.jpg",
    "peanut": "https://example.invalid/peanut.jpg",
    "peanut_butter": "https://example.invalid/peanut_butter.jpg",
    "pear": "https://example.invalid/pear.jpg",
    "pepper_egg": "https://example.invalid/pepper_egg.jpg",
    "pepper_pork": "https://example.invalid/pepper_pork.jpg",
    "pineapple": "https://example.invalid/pineapple.jpg",
    "pistachio": "https://example.invalid/pistachio.jpg",
    "pizza": "https://example.invalid/pizza.jpg",
    "pomegranate": "https://example.invalid/pomegranate.jpg",
    "pomelo": "https://example.invalid/pomelo.jpg",
    "popcorn": "https://example.invalid/popcorn.jpg",
    "pork_belly": "https://example.invalid/pork_belly.jpg",
    "pork_lean": "https://example.invalid/pork_lean.jpg",
    "pork_rib": "https://example.invalid/pork_rib.jpg",
    "potato": "https://example.invalid/potato.jpg",
    "pudding": "https://example.invalid/pudding.jpg",
    "pumpkin": "https://example.invalid/pumpkin.jpg",
    "pumpkin_congee": "https://example.invalid/pumpkin_congee.jpg",
    "purple_potato": "https://example.invalid/purple_potato.jpg",
    "quinoa": "https://example.invalid/quinoa.jpg",
    "radish": "https://example.invalid/radish.jpg",
    "red_bean_soup": "https://example.invalid/red_bean_soup.jpg",
    "rice_bowl": "https://example.invalid/rice_bowl.jpg",
    "rice_brown": "https://example.invalid/rice_brown.jpg",
    "rice_cooked": "https://example.invalid/rice_cooked.jpg",
    "roast_meat_rice": "https://example.invalid/roast_meat_rice.jpg",
    "roasted_cold_noodle": "https://example.invalid/roasted_cold_noodle.jpg",
    "roujiamo": "https://example.invalid/roujiamo.jpg",
    "saliva_chicken": "https://example.invalid/saliva_chicken.jpg",
    "salmon": "https://example.invalid/salmon.jpg",
    "salted_egg": "https://example.invalid/salted_egg.jpg",
    "sandwich": "https://example.invalid/sandwich.jpg",
    "scallion_pancake": "https://example.invalid/scallion_pancake.jpg",
    "seafood_soup": "https://example.invalid/seafood_soup.jpg",
    "sesame_paste": "https://example.invalid/sesame_paste.jpg",
    "shaobing": "https://example.invalid/shaobing.jpg",
    "shaomai": "https://example.invalid/shaomai.jpg",
    "shiitake": "https://example.invalid/shiitake.jpg",
    "shrimp": "https://example.invalid/shrimp.jpg",
    "shrimp_meat": "https://example.invalid/shrimp_meat.jpg",
    "soda_cracker": "https://example.invalid/soda_cracker.jpg",
    "sour_pepper_soup": "https://example.invalid/sour_pepper_soup.jpg",
    "sour_potato": "https://example.invalid/sour_potato.jpg",
    "soy_milk": "https://example.invalid/soy_milk.jpg",
    "soy_sauce": "https://example.invalid/soy_sauce.jpg",
    "soybean": "https://example.invalid/soybean.jpg",
    "soybean_sprout": "https://example.invalid/soybean_sprout.jpg",
    "spinach": "https://example.invalid/spinach.jpg",
    "sports_drink": "https://example.invalid/sports_drink.jpg",
    "squid": "https://example.invalid/squid.jpg",
    "steak": "https://example.invalid/steak.jpg",
    "steamed_egg": "https://example.invalid/steamed_egg.jpg",
    "steamed_fish": "https://example.invalid/steamed_fish.jpg",
    "stir_beef": "https://example.invalid/stir_beef.jpg",
    "stir_greens": "https://example.invalid/stir_greens.jpg",
    "strawberry": "https://example.invalid/strawberry.jpg",
    "sugar": "https://example.invalid/sugar.jpg",
    "sunflower_seed": "https://example.invalid/sunflower_seed.jpg",
    "sushi": "https://example.invalid/sushi.jpg",
    "sweet_loin": "https://example.invalid/sweet_loin.jpg",
    "sweet_potato": "https://example.invalid/sweet_potato.jpg",
    "tangyuan": "https://example.invalid/tangyuan.jpg",
    "tofu_egg": "https://example.invalid/tofu_egg.jpg",
    "tofu_north": "https://example.invalid/tofu_north.jpg",
    "tofu_south": "https://example.invalid/tofu_south.jpg",
    "tomato": "https://example.invalid/tomato.jpg",
    "tomato_beef": "https://example.invalid/tomato_beef.jpg",
    "tomato_cauliflower": "https://example.invalid/tomato_cauliflower.jpg",
    "tomato_egg": "https://example.invalid/tomato_egg.jpg",
    "tomato_egg_soup": "https://example.invalid/tomato_egg_soup.jpg",
    "tremella_soup": "https://example.invalid/tremella_soup.jpg",
    "trotter_rice": "https://example.invalid/trotter_rice.jpg",
    "trotters": "https://example.invalid/trotters.jpg",
    "twice_pork": "https://example.invalid/twice_pork.jpg",
    "vegetable_oil": "https://example.invalid/vegetable_oil.jpg",
    "vinegar": "https://example.invalid/vinegar.jpg",
    "vinegar_cabbage": "https://example.invalid/vinegar_cabbage.jpg",
    "walnut": "https://example.invalid/walnut.jpg",
    "watermelon": "https://example.invalid/watermelon.jpg",
    "wine_red": "https://example.invalid/wine_red.jpg",
    "wintermelon": "https://example.invalid/wintermelon.jpg",
    "wintermelon_ribs": "https://example.invalid/wintermelon_ribs.jpg",
    "xiaolongbao": "https://example.invalid/xiaolongbao.jpg",
    "yam": "https://example.invalid/yam.jpg",
    "yogurt": "https://example.invalid/yogurt.jpg",
    "yogurt_greek": "https://example.invalid/yogurt_greek.jpg",
    "youmaicai": "https://example.invalid/youmaicai.jpg",
    "youtiao": "https://example.invalid/youtiao.jpg",
    "yuxiang_pork": "https://example.invalid/yuxiang_pork.jpg",
    "zongzi": "https://example.invalid/zongzi.jpg",
    "zongzi_sweet": "https://example.invalid/zongzi_sweet.jpg",
]

// 写法 B：字符串常量 + 运行期切分（0.3.6 的新写法）
let idList = """
        almond americano ants_tree apple asparagus avocado
        baby_cabbage bacon baijiu banana baozi bass
        beef_jerky beef_lean beef_noodle beef_roll beer bibimbap
        bitter_melon blueberry boiled_chicken boiled_pork_slices borscht braised_chicken_rice
        braised_eggplant braised_hairtail braised_pork braised_ribs bread_toast bread_whole
        brisket broccoli burger butter cabbage carrot
        cashew celery_pork century_egg_congee cf_americano cf_cappuccino cf_caramel_macchiato
        cf_cheese_foam_tea cf_coconut_latte cf_fruit_tea cf_hot_cocoa cf_latte cf_lemon_tea
        cf_mango_pomelo cf_matcha_latte cf_milk_coffee cf_milk_tea cf_mocha cf_oat_latte
        cf_taro_boba changfen cheese cherry cherry_tomato chicken_breast
        chicken_leg chicken_nugget chicken_pot chicken_soup chicken_wing chips
        clam cola cola_wings cola_zero cold_cucumber cold_fungus
        congee corn corn_ribs crab cream_cake curry_chicken
        curry_rice d2_americano_iced d2_beef_ball_soup d2_beef_chow_fun d2_beef_rice d2_beef_tendon
        d2_big_plate_chicken d2_black_bean d2_blanched_shrimp d2_braised_noodles_bean d2_braised_pork_rice d2_braised_sea_cucumber
        d2_brown_sugar_milk_tea d2_butter_cookie d2_caesar_salad d2_cauliflower d2_celery d2_char_siu
        d2_cheese_grape_tea d2_cheese_slice d2_cheese_stick d2_chestnut d2_chicken_feet d2_chicken_popcorn
        d2_chicken_salad d2_chicken_wrap d2_chickpea d2_chili_oil d2_chocolate_milk d2_chopped_pepper_fish_head
        d2_claypot_rice d2_coconut_meat d2_coconut_water d2_condensed_milk d2_cookie_chocolate d2_cream
        d2_dongpo_pork d2_double_burger d2_dried_beancurd_snack d2_durian d2_edamame d2_egg_pancake
        d2_egg_roll d2_fish_fragrant_eggplant d2_fish_tofu d2_flat_white d2_fresh_soy_milk d2_fried_chicken_thigh
        d2_fried_chicken_wing d2_fujian_wonton d2_geda_soup d2_glutinous_cake d2_glutinous_rice_roll d2_goose_meat
        d2_grape_purple d2_guilin_rice_noodle d2_gummy d2_guobaorou d2_hand_grabbed_lamb d2_hazelnut
        d2_hot_dry_noodles d2_hotdog d2_hp_crispy_pork d2_hp_duck_blood d2_hp_thousand_tripe d2_hulatang
        d2_ice_cream_cone d2_konjac_snack d2_lamb_chop d2_lanzhou_noodles d2_liangfen d2_loofah
        d2_mapo_rice d2_marshmallow d2_milk_candy d2_milk_oatmeal d2_northeast_stew d2_onion_ring
        d2_oolong_tea d2_papaya d2_pea_shoot d2_pear_juice d2_pepper_pork_liver d2_persimmon
        d2_pigeon d2_pine_nut d2_plum d2_popsicle_fruit d2_pork_bun d2_pork_chop_rice
        d2_pork_ear d2_pork_heart d2_pork_jerky d2_pork_liver d2_potato_salad d2_potato_stew_beef
        d2_potato_vermicelli d2_pumpkin_bun d2_quail_egg d2_radish_rib_soup d2_rice_ball d2_rice_cake_soup
        d2_rice_cracker d2_roast_duck d2_salt_baked_chicken d2_salted_duck d2_salted_milk_tea d2_sandwich_egg
        d2_sauerkraut_fish d2_scallion_oil_noodles d2_seaweed_cracker d2_seaweed_egg_soup d2_seaweed_roll d2_sesame_ball
        d2_shaxian_noodles d2_shrimp_cracker d2_shuizhu_beef d2_soda_cracker_cream d2_soybean_trotter d2_sparkling_water
        d2_spicy_chicken_burger d2_spicy_crayfish d2_sports_water d2_sprite d2_steamed_roll d2_stinky_tofu
        d2_suan_cai_pork d2_sweet_sour_fish d2_swiss_roll d2_tea_egg d2_tofu_pudding d2_tofu_skin_sheet
        d2_tomato_egg_rice d2_veggie_bun d2_wafer d2_westlake_fish d2_wheat_noodle_soup d2_whole_milk_powder
        d2_wonton d2_wonton_noodles d2_xianggu_rice d2_yam_rib_soup d2_yanduxian d2_yangrou_paomo
        d2_youmian_kao d2_zhajiang_noodles dark_chocolate disanxian donut doubanjiang
        dragon_fruit dried_tofu dry_beans dry_cauliflower dry_four_season duck
        duck_breast dumpling egg_boiled egg_fried egg_fried_rice egg_tart
        egg_white eggplant eight_treasure enoki fried_chicken fried_dumpling
        fried_noodles fried_peanuts fried_rice fried_rice_noodle fries fungus
        fuzhu garlic_broccoli garlic_pork garlic_sprout_pork glutinous_rice grape
        green_pepper guamian guotie hairtail ham_sausage hami_melon
        hand_cabbage hand_pancake hefen honey hot_sour_noodles hp_beef_ball
        hp_beef_omasum hp_beef_slice hp_beef_tripe hp_broad_vermicelli hp_broth_mushroom hp_broth_tomato
        hp_crab_stick hp_duck_intestine hp_egg_dumpling hp_fish_ball hp_lamb_roll hp_lotus_root_slice
        hp_potato_slice hp_sesame_dip hp_sesame_oil_dip hp_shrimp_dumpling hp_shrimp_paste hp_sweet_potato_noodle
        hp_tofu_skin hp_winter_melon_slice ice_bar ice_cream instant_noodle jelly
        jianbing kelp ketchup kiwi kumquat kungpao_chicken
        lamb_lean lard latiao leek leek_egg lemon
        lettuce liangpi lianou_fen lotus_root luncheon_meat luosifen
        lychee malatang mango mantou maocai maoxuewang
        mapo_tofu marinated_egg mayonnaise milk_skim milk_tea milk_whole
        millet_congee mixian mung_bean mung_soup mung_sprout mushroom_chicken
        niangao noodles oats oden okra omurice
        onion orange orange_juice oreo oyster_sauce pasta
        peach peanut peanut_butter pear pepper_egg pepper_pork
        pineapple pistachio pizza pomegranate pomelo popcorn
        pork_belly pork_lean pork_rib potato pudding pumpkin
        pumpkin_congee purple_potato quinoa radish red_bean_soup rice_bowl
        rice_brown rice_cooked roast_meat_rice roasted_cold_noodle roujiamo saliva_chicken
        salmon salted_egg sandwich scallion_pancake seafood_soup sesame_paste
        shaobing shaomai shiitake shrimp shrimp_meat soda_cracker
        sour_pepper_soup sour_potato soy_milk soy_sauce soybean soybean_sprout
        spinach sports_drink squid steak steamed_egg steamed_fish
        stir_beef stir_greens strawberry sugar sunflower_seed sushi
        sweet_loin sweet_potato tangyuan tofu_egg tofu_north tofu_south
        tomato tomato_beef tomato_cauliflower tomato_egg tomato_egg_soup tremella_soup
        trotter_rice trotters twice_pork vegetable_oil vinegar vinegar_cabbage
        walnut watermelon wine_red wintermelon wintermelon_ribs xiaolongbao
        yam yogurt yogurt_greek youmaicai youtiao yuxiang_pork
        zongzi zongzi_sweet
    """
let idSet: Set<String> = Set(idList.split(whereSeparator: { $0.isWhitespace }).map(String.init))

func check(_ label: String, _ body: () -> Int) {
    print("\(label) ... ", terminator: "")
    fflush(stdout)
    print("OK，得到 \(body()) 项")
}

check("A 字典字面量") { literalMap.count }
check("B 字符串常量") { idSet.count }

let same = Set(literalMap.keys) == idSet
print("两种写法 id 集合一致：\(same)")
print("A 的 key 数：\(literalMap.count)，唯一 key 数：\(Set(literalMap.keys).count)")
print("结论：A 与 B 都能构造 —— 若真机仍然崩在 A，则问题不在 key 重复")
