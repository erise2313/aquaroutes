import 'providers/web_locale_provider.dart';

/// Bilingual (EN/Tagalog) strings for the public website's navigation,
/// headings, and key copy. Deliberately NOT exhaustive -- long-form body
/// paragraphs (e.g. the full accreditation walk-through) stay English-only
/// for now rather than translating every sentence. The Tagalog here is
/// machine-quality, not native-reviewed -- worth a native speaker's check
/// before a real public launch.
class WebStrings {
  WebStrings._();

  static const Map<String, Map<WebLocale, String>> _strings = {
    // Nav
    'nav_home': {WebLocale.en: 'Home', WebLocale.tl: 'Home'},
    'nav_about': {WebLocale.en: 'About', WebLocale.tl: 'Tungkol Sa Amin'},
    'nav_how_it_works': {WebLocale.en: 'How Accreditation Works', WebLocale.tl: 'Proseso ng Akreditasyon'},
    'nav_for_owners': {WebLocale.en: 'For Station Owners', WebLocale.tl: 'Para sa May-ari ng Istasyon'},
    'nav_news': {WebLocale.en: 'News', WebLocale.tl: 'Balita'},
    'nav_stations': {WebLocale.en: 'Stations', WebLocale.tl: 'Mga Istasyon'},
    'nav_contact': {WebLocale.en: 'Contact', WebLocale.tl: 'Makipag-ugnayan'},
    'nav_login': {WebLocale.en: 'Login', WebLocale.tl: 'Mag-login'},
    'nav_register': {WebLocale.en: 'Register a Station', WebLocale.tl: 'Magparehistro ng Istasyon'},

    // Hero
    'hero_title': {WebLocale.en: 'Every jug, certified.', WebLocale.tl: 'Bawat galong, sertipikado.'},
    'hero_subtitle': {
      WebLocale.en:
          'GENTRI WASA reviews and accredits every water refilling station in General Trias, Cavite -- so the seal on a station means something before you ever order a drop.',
      WebLocale.tl:
          'Sinusuri at inaakredita ng GENTRI WASA ang bawat water refilling station sa General Trias, Cavite -- para may kahulugan ang selyo sa istasyon bago ka pa mag-order.',
    },
    'hero_register_cta': {WebLocale.en: 'Register Your Station', WebLocale.tl: 'Irehistro ang Iyong Istasyon'},
    'hero_admin_login_cta': {WebLocale.en: 'WASA Admin Login', WebLocale.tl: 'WASA Admin Login'},

    // Stats
    'stats_accredited_stations': {WebLocale.en: 'Accredited Stations', WebLocale.tl: 'Akreditadong Istasyon'},
    'stats_barangays_served': {WebLocale.en: 'Barangays Served', WebLocale.tl: 'Mga Barangay na Sinisilbihan'},

    // Homepage teasers
    'home_news_section_title': {WebLocale.en: 'Association News', WebLocale.tl: 'Balita ng Asosasyon'},
    'home_view_all': {WebLocale.en: 'View All', WebLocale.tl: 'Tingnan Lahat'},
    'home_stations_section_title': {WebLocale.en: 'Verified Member Stations', WebLocale.tl: 'Beripikadong mga Istasyon'},

    // About
    'about_title': {WebLocale.en: 'About GENTRI WASA', WebLocale.tl: 'Tungkol sa GENTRI WASA'},
    'about_intro': {
      WebLocale.en:
          'GENTRI WASA exists to bring order and accountability to the water refilling industry in General Trias -- so residents can trust the water they order, and legitimate station owners are protected from unlicensed ("colorum") competition.',
      WebLocale.tl:
          'Ang GENTRI WASA ay naglalayong magdala ng kaayusan at pananagutan sa industriya ng water refilling sa General Trias -- upang mapagkakatiwalaan ng mga residente ang tubig na kanilang inoorder, at mapangalagaan ang mga lehitimong may-ari ng istasyon mula sa "colorum" na kompetisyon.',
    },

    // How accreditation works
    'how_it_works_title': {WebLocale.en: 'How Accreditation Works', WebLocale.tl: 'Paano Gumagana ang Akreditasyon'},
    'how_it_works_intro': {
      WebLocale.en: 'Every accredited station has gone through the same review process, end to end:',
      WebLocale.tl: 'Bawat akreditadong istasyon ay dumaan sa parehong proseso ng pagsusuri:',
    },

    // For station owners
    'for_owners_title': {WebLocale.en: 'For Station Owners', WebLocale.tl: 'Para sa mga May-ari ng Istasyon'},
    'for_owners_intro': {
      WebLocale.en: 'Joining GENTRI WASA gives your station official recognition, access to the worker accountability registry, and a voice in association-wide pricing policy.',
      WebLocale.tl: 'Ang pagsali sa GENTRI WASA ay nagbibigay sa iyong istasyon ng opisyal na pagkilala, access sa worker accountability registry, at boses sa patakaran ng presyo sa buong asosasyon.',
    },
    'for_owners_cta': {WebLocale.en: 'Register Your Station', WebLocale.tl: 'Irehistro ang Iyong Istasyon'},

    // News
    'news_title': {WebLocale.en: 'Association News', WebLocale.tl: 'Balita ng Asosasyon'},

    // Stations directory
    'stations_title': {WebLocale.en: 'Verified Member Stations', WebLocale.tl: 'Beripikadong mga Istasyon'},
    'stations_search_hint': {WebLocale.en: 'Search by station name...', WebLocale.tl: 'Maghanap ng pangalan ng istasyon...'},
    'stations_filter_water_type': {WebLocale.en: 'Water Type', WebLocale.tl: 'Uri ng Tubig'},
    'stations_filter_barangay': {WebLocale.en: 'Barangay', WebLocale.tl: 'Barangay'},

    // Contact
    'contact_title': {WebLocale.en: 'Contact WASA', WebLocale.tl: 'Makipag-ugnayan sa WASA'},
    'contact_intro': {
      WebLocale.en: 'Have a question, complaint, or want to learn more? Reach out to the association directly.',
      WebLocale.tl: 'May tanong, reklamo, o gusto pang malaman? Makipag-ugnayan direkta sa asosasyon.',
    },

    // Footer
    'footer_quick_links': {WebLocale.en: 'Quick Links', WebLocale.tl: 'Mabilisang Link'},
    'footer_office': {WebLocale.en: 'Office', WebLocale.tl: 'Opisina'},
    'footer_rights': {WebLocale.en: 'All rights reserved.', WebLocale.tl: 'Lahat ng karapatan ay nakalaan.'},
    'footer_resources': {WebLocale.en: 'Resources', WebLocale.tl: 'Mga Kapaki-pakinabang'},

    // FAQ
    'faq_title': {WebLocale.en: 'Frequently Asked Questions', WebLocale.tl: 'Mga Madalas Itanong'},
    'faq_intro': {
      WebLocale.en: 'Common questions about accreditation, ordering, and how GENTRI WASA works.',
      WebLocale.tl: 'Mga karaniwang tanong tungkol sa akreditasyon, pag-order, at kung paano gumagana ang GENTRI WASA.',
    },

    // Verify accreditation
    'verify_title': {WebLocale.en: 'Verify a Station\'s Accreditation', WebLocale.tl: 'I-verify ang Akreditasyon ng Istasyon'},
    'verify_intro': {
      WebLocale.en: 'Confirm whether a water refilling station is currently WASA-accredited before you order.',
      WebLocale.tl: 'Kumpirmahin kung ang isang water refilling station ay kasalukuyang akreditado ng WASA bago mag-order.',
    },

    // Jug clearinghouse explainer
    'jug_clearinghouse_title': {WebLocale.en: 'The Jug Clearinghouse', WebLocale.tl: 'Ang Jug Clearinghouse'},
    'jug_clearinghouse_intro': {
      WebLocale.en: 'How member stations fairly settle empty-jug exchanges with each other.',
      WebLocale.tl: 'Kung paano makatarungang inaayos ng mga miyembrong istasyon ang palitan ng mga walang-lamang lalagyan.',
    },

    // Resources
    'resources_title': {WebLocale.en: 'Resources', WebLocale.tl: 'Mga Kapaki-pakinabang'},
    'resources_intro': {
      WebLocale.en: 'Checklists, schedules, and documents for station owners.',
      WebLocale.tl: 'Mga checklist, iskedyul, at dokumento para sa mga may-ari ng istasyon.',
    },

    // Events
    'events_title': {WebLocale.en: 'Events', WebLocale.tl: 'Mga Kaganapan'},
    'events_intro': {
      WebLocale.en: 'Upcoming general assemblies, seminars, and association activities.',
      WebLocale.tl: 'Paparating na mga pangkalahatang asembliya, seminar, at aktibidad ng asosasyon.',
    },
  };

  static String t(WebLocale locale, String key) {
    return _strings[key]?[locale] ?? _strings[key]?[WebLocale.en] ?? key;
  }
}
