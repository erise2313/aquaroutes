import 'package:flutter/material.dart';

import '../../models/membership.dart';

/// One page of the first-run tour.
typedef TourPage = ({IconData icon, String title, String body});

/// One question on the Help screen.
typedef HelpQuestion = ({String question, String answer});

/// Every role gets a three-page tour the first time it signs in, and a Help
/// screen. Kept in one file, in plain English, so a Tagalog version is one
/// translation job rather than a hunt through screens.
List<TourPage> tourPagesFor(AppRole role) => switch (role) {
      AppRole.publicConsumer => const [
          (icon: Icons.verified_outlined, title: 'Order from checked stations', body: 'Every station here is listed with GenTri WASA. The gold badge means accredited: permits current, water tested.'),
          (icon: Icons.local_shipping_outlined, title: 'Follow your order', body: 'Orders shows each step -- assigned, out for delivery, delivered -- with the time it happened.'),
          (icon: Icons.flag_outlined, title: 'Something wrong? Tell WASA', body: 'From an order or a station, "Report a problem" goes to the association. The station is not told who reported it.'),
        ],
      AppRole.stationOwner => const [
          (icon: Icons.folder_shared_outlined, title: 'Keep your permits current', body: 'The Permit vault shows what is done and what is left. You get reminders 30 and 7 days before anything expires.'),
          (icon: Icons.list_alt, title: 'Take every order in one place', body: 'App orders arrive by themselves. Add phone and walk-in customers with New order in Orders.'),
          (icon: Icons.mark_email_unread_outlined, title: 'Hear from the association', body: 'WASA notices and customer reports come to you here. Answer them in writing, any time.'),
        ],
      AppRole.stationStaff => const [
          (icon: Icons.list_alt, title: 'Run the counter', body: 'See new orders as they arrive, assign a driver, and add phone and walk-in orders.'),
          (icon: Icons.local_shipping_outlined, title: 'Track deliveries', body: 'Track shows where each driver is. Drivers are read-only for you; the owner manages them.'),
          (icon: Icons.help_outline, title: 'Ask the owner', body: 'Prices, products, permits and settlements are the owner\'s. Ask them to change anything there.'),
        ],
      AppRole.driver => const [
          (icon: Icons.assignment_outlined, title: 'Your deliveries', body: 'Orders assigned to you appear on your dashboard. Start one to share your location with the customer.'),
          (icon: Icons.badge_outlined, title: 'Your clearance', body: 'Keep your licence uploaded and current. You get a reminder before it expires.'),
          (icon: Icons.report_problem_outlined, title: 'If a delivery fails', body: 'Mark it failed with the reason -- nobody home, wrong address -- so the station can follow up.'),
        ],
      AppRole.wasaAdmin || AppRole.wasaSuperadmin => const [
          (icon: Icons.fact_check_outlined, title: 'Review the queues', body: 'Permits, Workers and Reports show a count when something is waiting for an officer.'),
          (icon: Icons.gavel_outlined, title: 'Keep a written record', body: 'Use Cases for any issue with a station: what happened, the evidence, the decision. Every change is in Activity.'),
          (icon: Icons.privacy_tip_outlined, title: 'Customers stay private', body: 'Orders hide who placed them unless a report about that order is on file.'),
        ],
    };

List<HelpQuestion> helpQuestionsFor(AppRole role) => switch (role) {
      AppRole.publicConsumer => const [
          (question: 'What does "Accredited" mean?', answer: 'The station\'s required permits are approved and current, and it passed its last water test. "Lapsed" means a permit expired and has not been renewed.'),
          (question: 'How do I order again?', answer: 'Home shows "My station" with Order again. Or open Orders and tap Order again on a delivered order.'),
          (question: 'My water tastes wrong. What do I do?', answer: 'Open the order, tap "Report a problem to WASA", choose what went wrong, and add a photo if you can.'),
          (question: 'Can I cancel?', answer: 'Yes, until the driver sets out. After that, call the station.'),
        ],
      AppRole.stationOwner => const [
          (question: 'Why does my station say "Renewal due"?', answer: 'A required permit expired or is waiting for review. You keep your badge during the grace period; upload the renewal in the Permit vault.'),
          (question: 'How do I add a phone order?', answer: 'Orders, then New order. Choose Phone order, the product and quantity, and either pickup or a delivery pin.'),
          (question: 'How do I add counter staff?', answer: 'Team shows your staff code. Staff register in the app with "I work at a station" and that code.'),
          (question: 'Who sees my cost calculator?', answer: 'Only you. WASA and other stations cannot read it.'),
        ],
      AppRole.stationStaff => const [
          (question: 'How do I assign a driver?', answer: 'Open the order in Orders and choose an available driver.'),
          (question: 'Why can\'t I change prices?', answer: 'Prices, products and permits are the owner\'s. Ask the owner.'),
        ],
      AppRole.driver => const [
          (question: 'My clearance says pending. Can I deliver?', answer: 'Not yet. WASA checks your documents first; you are notified when you are cleared.'),
          (question: 'How do I update my licence?', answer: 'Profile, then upload the new licence with its expiry date.'),
        ],
      AppRole.wasaAdmin || AppRole.wasaSuperadmin => const [
          (question: 'How does a station lapse?', answer: 'The daily check marks a station "Renewal due" when a required permit expires, and "Lapsed" after the grace period in Settings. Both the owner and officers are told.'),
          (question: 'Why can\'t I review this station?', answer: 'You own, staff or drive for it. Another officer must review it.'),
          (question: 'How do I add an officer?', answer: 'A super admin uses Officers to promote an existing account by email.'),
        ],
    };
