import Foundation

/// 本地食物库的配图索引。
///
/// 图片来自下厨房搜索页，按食物名匹配；匹配不上的条目（成分表那批食材、中式成菜）
/// 没有配图，界面按分类退回 SF Symbol 图标。
///
/// 0.3.5 起这 434 张图已经压到 256×256 打包进 Assets 的 FoodImages 组，断网也有图，
/// 下面这段 id 只用来判断「这个食物有没有配图」。
///
/// 这里刻意写成一段空白分隔的 id 常量再切分，而不是 [String: String] 或 Set 字面量：
/// 大块的字面量每个元素都是一次运行期构造，会走标准库的 dictionaryLiteral 并对重复
/// key 做 precondition，元素一多就有在真机上直接 trap 的风险。0.3.4 build 7 和
/// 0.3.5 build 8 两次崩溃的栈帧都停在 FoodImages 的一次性初始化上，就是踩了这个。
/// 改成字符串常量后，切分与建集合都是普通代码路径，没有断言可踩。
enum FoodImages {
    private static let idList = """
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

    private static let ids: Set<String> = Set(
        idList.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    )

    /// 打包进 App 的配图资源名；这个 id 没配图时返回 nil。
    static func assetName(for id: String) -> String? {
        ids.contains(id) ? "food_" + id : nil
    }

    /// 配图条目总数，供校验脚本与调试使用。
    static var count: Int { ids.count }
}
