import 'package:get/get.dart';

class WolverixTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'en_US': {
      // General
      'app_name': 'Wolverix',
      'loading': 'Loading...',
      'error': 'Error',
      'success': 'Success',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'ok': 'OK',
      'yes': 'Yes',
      'no': 'No',
      'back': 'Back',
      'next': 'Next',
      'done': 'Done',
      'save': 'Save',
      'delete': 'Delete',
      'edit': 'Edit',
      'close': 'Close',

      // Auth
      'login': 'Login',
      'register': 'Register',
      'logout': 'Logout',
      'email': 'Email',
      'password': 'Password',
      'username': 'Username',
      'confirm_password': 'Confirm Password',
      'forgot_password': 'Forgot Password?',
      'no_account': "Don't have an account?",
      'have_account': 'Already have an account?',
      'sign_up': 'Sign Up',
      'sign_in': 'Sign In',

      // Home
      'home': 'Home',
      'create_room': 'Create Room',
      'join_room': 'Join Room',
      'available_rooms': 'Available Rooms',
      'no_rooms': 'No rooms available',
      'profile': 'Profile',
      'settings': 'Settings',

      // Room
      'room': 'Room',
      'room_name': 'Room Name',
      'room_code': 'Room Code',
      'max_players': 'Max Players',
      'private_room': 'Private Room',
      'players': 'Players',
      'ready': 'Ready',
      'not_ready': 'Not Ready',
      'start_game': 'Start Game',
      'leave_room': 'Leave Room',
      'kick_player': 'Kick Player',
      'enter_code': 'Enter Room Code',
      'waiting_players': 'Waiting for players...',
      'all_ready': 'All players ready!',

      // Game
      'game': 'Game',
      'your_role': 'Your Role',
      'alive': 'Alive',
      'dead': 'Dead',
      'vote': 'Vote',
      'skip_vote': 'Skip Vote',
      'discussion_time': 'Discussion Time',
      'voting_time': 'Voting Time',
      'night_time': 'Night Time',

      // Roles
      'role_werewolf': 'Werewolf',
      'role_villager': 'Villager',
      'role_seer': 'Seer',
      'role_witch': 'Witch',
      'role_hunter': 'Hunter',
      'role_cupid': 'Cupid',
      'role_bodyguard': 'Bodyguard',
      'role_mayor': 'Mayor',
      'role_medium': 'Medium',
      'role_tanner': 'Tanner',
      'role_little_girl': 'Little Girl',

      // Role descriptions
      'desc_werewolf': 'Hunt villagers at night. Know your fellow wolves.',
      'desc_villager': 'Find and eliminate the werewolves to survive.',
      'desc_seer': 'Divine one player each night to learn their true nature.',
      'desc_witch':
          'Use your heal potion to save, or poison to kill. Once each.',
      'desc_hunter': 'If killed, shoot one player to take them down with you.',
      'desc_cupid': 'Choose two lovers on night one. They share their fate.',
      'desc_bodyguard': 'Protect one player each night from werewolf attacks.',
      'desc_mayor': 'Can reveal for a double vote. Succession passes on death.',
      'desc_medium': 'Speak with the dead to gather information.',
      'desc_tanner': 'Win alone if lynched by the village.',
      'desc_little_girl': 'Peek at werewolves at night, but risk being caught.',

      // Phases
      'phase_night': 'Night Falls',
      'phase_cupid': "Cupid's Turn",
      'phase_werewolf': 'Werewolves Hunt',
      'phase_seer': "Seer's Vision",
      'phase_witch': "Witch's Choice",
      'phase_bodyguard': 'Bodyguard Protects',
      'phase_day': 'Village Discussion',
      'phase_voting': 'Vote for Suspect',
      'phase_defense': 'Defense Speech',
      'phase_final': 'Final Judgment',
      'phase_hunter': "Hunter's Revenge",
      'phase_mayor': 'Mayor Election',
      'phase_gameover': 'Game Over',

      // Game events
      'player_killed': '@name was killed',
      'player_lynched': '@name was lynched',
      'no_death': 'No one died tonight',
      'no_lynch': 'The village decided not to lynch anyone',
      'werewolves_win': 'Werewolves Win!',
      'villagers_win': 'Villagers Win!',
      'lovers_win': 'Lovers Win!',
      'tanner_wins': 'Tanner Wins!',

      // Voice
      'mute': 'Mute',
      'unmute': 'Unmute',
      'speaker': 'Speaker',
      'voice_chat': 'Voice Chat',

      // Errors
      'error_network': 'Network error. Please check your connection.',
      'error_invalid_credentials': 'Invalid email or password',
      'error_room_full': 'Room is full',
      'error_room_not_found': 'Room not found',
      'error_not_enough_players': 'Need at least 5 players to start',
      'error_not_all_ready': 'All players must be ready',
    },

    'fr_FR': {
      // General
      'app_name': 'Wolverix',
      'loading': 'Chargement...',
      'error': 'Erreur',
      'success': 'Succès',
      'cancel': 'Annuler',
      'confirm': 'Confirmer',
      'ok': 'OK',
      'yes': 'Oui',
      'no': 'Non',
      'back': 'Retour',
      'next': 'Suivant',
      'done': 'Terminé',
      'save': 'Sauvegarder',
      'delete': 'Supprimer',
      'edit': 'Modifier',
      'close': 'Fermer',

      // Auth
      'login': 'Connexion',
      'register': "S'inscrire",
      'logout': 'Déconnexion',
      'email': 'Email',
      'password': 'Mot de passe',
      'username': "Nom d'utilisateur",
      'confirm_password': 'Confirmer le mot de passe',
      'forgot_password': 'Mot de passe oublié ?',
      'no_account': "Pas de compte ?",
      'have_account': 'Déjà un compte ?',
      'sign_up': "S'inscrire",
      'sign_in': 'Se connecter',

      // Roles
      'role_werewolf': 'Loup-Garou',
      'role_villager': 'Villageois',
      'role_seer': 'Voyante',
      'role_witch': 'Sorcière',
      'role_hunter': 'Chasseur',
      'role_cupid': 'Cupidon',
      'role_bodyguard': 'Garde du Corps',
      'role_mayor': 'Maire',
      'role_medium': 'Médium',
      'role_tanner': 'Tanneur',
      'role_little_girl': 'Petite Fille',

      // Game results
      'werewolves_win': 'Les Loups-Garous Gagnent !',
      'villagers_win': 'Les Villageois Gagnent !',
      'lovers_win': 'Les Amoureux Gagnent !',
      'tanner_wins': 'Le Tanneur Gagne !',
    },
  };
}
