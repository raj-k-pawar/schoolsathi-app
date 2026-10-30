/// Small in-app translator: the English text is the key.
/// Anything without a translation is shown in English.
class I18n {
  static String locale = 'en';

  static const names = {'en': 'English', 'hi': 'हिन्दी', 'mr': 'मराठी'};

  static const Map<String, Map<String, String>> _text = {
    'hi': {
      'Home': 'होम', 'Fees': 'फीस', 'Bus': 'बस', 'Alerts': 'सूचनाएँ', 'More': 'और', 'Profile': 'प्रोफ़ाइल',
      'Attendance': 'उपस्थिति', 'Homework': 'गृहकार्य', 'Notices': 'सूचना पट', 'Results': 'परिणाम', 'Timetable': 'समय सारणी',
      'Online tests': 'ऑनलाइन परीक्षा', 'Leave': 'छुट्टी', 'Chat': 'संदेश', 'Pickup': 'पिकअप', 'Calendar': 'कैलेंडर', 'Gallery': 'गैलरी',
      'Today': 'आज', 'Present': 'उपस्थित', 'Absent': 'अनुपस्थित', 'Late': 'देर से', 'Half day': 'आधा दिन', 'On leave': 'छुट्टी पर',
      'Not marked yet': 'अभी दर्ज नहीं', 'Fees due': 'बकाया फीस', 'No dues': 'कोई बकाया नहीं', 'Pay now': 'अभी भुगतान करें',
      'School bus': 'स्कूल बस', 'Track bus': 'बस देखें', 'Sign out': 'साइन आउट', 'Language': 'भाषा',
      'Mobile number': 'मोबाइल नंबर', 'Sign in': 'साइन इन करें', 'Change password': 'पासवर्ड बदलें', 'Notifications': 'सूचनाएँ',
      'Good morning': 'सुप्रभात', 'Good afternoon': 'नमस्कार', 'Good evening': 'शुभ संध्या',
      'Everything in one place': 'सब कुछ एक जगह', 'Latest alerts': 'नई सूचनाएँ', 'See all': 'सभी देखें',
      'Apply for leave': 'छुट्टी के लिए आवेदन', 'Reason': 'कारण', 'From': 'से', 'To': 'तक', 'Submit': 'जमा करें',
      'Receipts': 'रसीदें', 'Due': 'देय', 'Paid': 'भुगतान हुआ', 'Retry': 'फिर कोशिश करें', 'Nothing here yet': 'अभी यहाँ कुछ नहीं है',
      'Not taking the bus today': 'आज बस नहीं लेंगे', 'Bus is on the way': 'बस रास्ते में है', 'No trip is running now': 'अभी कोई ट्रिप नहीं चल रही',
      'Privacy and consent': 'गोपनीयता और सहमति', 'Type a message': 'संदेश लिखें', 'My children': 'मेरे बच्चे',
      'Attendance this year': 'इस वर्ष की उपस्थिति', 'Class': 'कक्षा', 'Send': 'भेजें', 'Cancel': 'रद्द करें', 'Save': 'सहेजें',
    },
    'mr': {
      'Home': 'होम', 'Fees': 'फी', 'Bus': 'बस', 'Alerts': 'सूचना', 'More': 'अधिक', 'Profile': 'प्रोफाइल',
      'Attendance': 'हजेरी', 'Homework': 'गृहपाठ', 'Notices': 'सूचना फलक', 'Results': 'निकाल', 'Timetable': 'वेळापत्रक',
      'Online tests': 'ऑनलाइन चाचण्या', 'Leave': 'रजा', 'Chat': 'संदेश', 'Pickup': 'पिकअप', 'Calendar': 'दिनदर्शिका', 'Gallery': 'गॅलरी',
      'Today': 'आज', 'Present': 'उपस्थित', 'Absent': 'गैरहजर', 'Late': 'उशिरा', 'Half day': 'अर्धा दिवस', 'On leave': 'रजेवर',
      'Not marked yet': 'अजून नोंद नाही', 'Fees due': 'थकीत फी', 'No dues': 'थकबाकी नाही', 'Pay now': 'आता भरा',
      'School bus': 'शाळेची बस', 'Track bus': 'बस पहा', 'Sign out': 'साइन आउट', 'Language': 'भाषा',
      'Mobile number': 'मोबाइल नंबर', 'Sign in': 'साइन इन करा', 'Change password': 'पासवर्ड बदला', 'Notifications': 'सूचना',
      'Good morning': 'सुप्रभात', 'Good afternoon': 'नमस्कार', 'Good evening': 'शुभ संध्या',
      'Everything in one place': 'सर्व काही एका ठिकाणी', 'Latest alerts': 'नवीन सूचना', 'See all': 'सर्व पहा',
      'Apply for leave': 'रजेसाठी अर्ज', 'Reason': 'कारण', 'From': 'पासून', 'To': 'पर्यंत', 'Submit': 'सादर करा',
      'Receipts': 'पावत्या', 'Due': 'देय', 'Paid': 'भरले', 'Retry': 'पुन्हा प्रयत्न करा', 'Nothing here yet': 'अजून इथे काही नाही',
      'Not taking the bus today': 'आज बस घेणार नाही', 'Bus is on the way': 'बस वाटेत आहे', 'No trip is running now': 'सध्या कोणतीही फेरी चालू नाही',
      'Privacy and consent': 'गोपनीयता आणि संमती', 'Type a message': 'संदेश लिहा', 'My children': 'माझी मुले',
      'Attendance this year': 'या वर्षाची हजेरी', 'Class': 'वर्ग', 'Send': 'पाठवा', 'Cancel': 'रद्द करा', 'Save': 'जतन करा',
    },
  };

  static String t(String english) => _text[locale]?[english] ?? english;
}

/// Shorthand used all over the UI.
String tr(String english) => I18n.t(english);
