extends Node
## Tum Turkce UI metinleri tek sozlukte. Kullanim: Tr.t(&"declare_war")
## Tek dilli MVP icin Godot'un CSV ceviri hattindan daha pratik.

const S := {
	# genel
	&"app_title": "MODERN CITY WAR",
	&"subtitle": "İki belediye başkanı, tek harita.",
	&"host_game": "Oyun Kur",
	&"join_game": "Oyuna Katıl",
	&"quit": "Çıkış",
	&"back": "Geri",
	&"connect": "Bağlan",
	&"ip_address": "Sunucu IP adresi",
	&"waiting_opponent": "Rakip bekleniyor...",
	&"your_ip_hint": "Arkadaşın bu makinenin IP'sine bağlanmalı (port 8910/UDP).",
	&"connecting": "Bağlanılıyor...",
	&"connected_waiting": "Bağlandı, oyun hazırlanıyor...",
	&"connection_failed": "Bağlantı kurulamadı",
	&"connection_lost": "Bağlantı koptu",
	&"version_mismatch": "Sürüm uyumsuz — iki tarafta da aynı sürüm olmalı",
	&"desync": "Harita uyuşmazlığı — bağlantı kesildi",
	&"match_started": "Maç başladı! Bol şans başkanım.",
	&"opponent_left": "Rakip oyundan ayrıldı",

	# kaynaklar
	&"wood": "Odun",
	&"stone": "Taş",
	&"food": "Yiyecek",
	&"money": "Para",
	&"pop": "Nüfus",

	# birimler
	&"worker": "İşçi",
	&"rifleman": "Piyade",
	&"sniper": "Nişancı",
	&"rpg": "RPG'ci",
	&"tank": "Tank",

	# binalar
	&"city_hall": "Belediye Binası",
	&"house": "Ev",
	&"greenhouse": "Sera",
	&"bank": "Banka",
	&"barracks": "Kışla",
	&"factory": "Fabrika",
	&"turret": "Taret",

	# savas durumu
	&"peace": "BARIŞ",
	&"war_countdown": "SAVAŞA %d sn",
	&"at_war": "SAVAŞ HALİ",
	&"declare_war": "Savaş İlan Et",
	&"war_declared_by_you": "Savaş ilan ettin! 30 saniye sonra çatışma serbest.",
	&"war_declared_by_enemy": "Rakip savaş ilan etti! 30 saniye sonra çatışma serbest.",
	&"war_began": "SAVAŞ BAŞLADI!",

	# komut/red mesajlari
	&"reject_no_res": "Yetersiz kaynak",
	&"reject_bad_spot": "Buraya inşa edilemez",
	&"reject_too_far": "Şehrinden çok uzak (en fazla 10 kare)",
	&"reject_pop_full": "Nüfus dolu — ev yap",
	&"reject_blocked": "Alan dolu",
	&"reject_queue_full": "Üretim kuyruğu dolu",
	&"reject_peace": "Barış halinde saldıramazsın",
	&"depleted": "Bir kaynak tükendi",

	# uretim / insaat
	&"build": "İnşa Et",
	&"train": "Üret",
	&"cancel": "İptal",
	&"under_construction": "İnşaat halinde",
	&"queue": "Kuyruk",

	# oyun sonu
	&"victory": "ZAFER!",
	&"defeat": "YENİLGİ",
	&"reason_destruction": "Belediye Binası yıkıldı",
	&"reason_metropolis": "Metropol hedefine ulaşıldı",
	&"reason_opponent_left": "Rakip oyundan ayrıldı",
	&"main_menu": "Ana Menü",
	&"metropolis_goal": "Metropol: %d/%d nüfus + her binadan 1",
	&"metro_short": "Metropol %d/%d | bina %d/%d",
	&"n_units": "%d birim",
}


static func t(key: StringName) -> String:
	return S.get(key, String(key))
