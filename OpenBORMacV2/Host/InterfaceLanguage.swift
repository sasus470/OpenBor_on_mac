import SwiftUI

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case english = "en", italian = "it", spanish = "es", portuguese = "pt"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .english: return "English"
        case .italian: return "Italiano"
        case .spanish: return "Español"
        case .portuguese: return "Português"
        }
    }
    var index: Int { Self.allCases.firstIndex(of: self)! }
}

final class InterfaceLanguagePreferences: ObservableObject {
    static let shared = InterfaceLanguagePreferences()
    @Published var language: InterfaceLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "interfaceLanguage") }
    }
    private init() {
        language = InterfaceLanguage(rawValue: UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "it") ?? .italian
    }
}

enum UIStrings {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, language: InterfaceLanguagePreferences.shared.language, arguments: arguments)
    }
    static func format(_ key: String, language: InterfaceLanguage, arguments: [CVarArg] = []) -> String {
        let value = translations[key]?[language.index] ?? key
        return arguments.isEmpty ? value : String(format: value, arguments: arguments)
    }
    // Each row uses the same order: English, Italian, Spanish, Portuguese.
    static let translations: [String: [String]] = [
        "Cancel": ["Cancel", "Annulla", "Cancelar", "Cancelar"],
        "Enable rewind": ["Enable rewind", "Attiva rewind", "Activar rebobinado", "Ativar rewind"],
        "Disable rewind": ["Disable rewind", "Disattiva rewind", "Desactivar rebobinado", "Desativar rewind"],
        "Rewind key": ["Rewind key", "Tasto rewind", "Tecla de rebobinado", "Tecla de rewind"],
        "Rewind conflict": ["Choose a different key from the quick menu.", "Scegli un tasto diverso da quello del menu rapido.", "Elige una tecla distinta a la del menu rapido.", "Escolha uma tecla diferente da do menu rapido."],
        "Rewind help": ["Press the key to pause and choose an earlier preview. Up to 15 seconds in half-second steps; history resets at level changes. Manual slots are unaffected.", "Premi il tasto per mettere in pausa e scegliere un'anteprima precedente. Fino a 15 secondi, a passi di mezzo secondo; la cronologia si azzera al cambio livello. Gli slot manuali restano invariati.", "Pulsa la tecla para pausar y elegir una vista previa anterior. Hasta 15 segundos en pasos de medio segundo; el historial se reinicia al cambiar de nivel. Los estados manuales no cambian.", "Pressione a tecla para pausar e escolher uma imagem anterior. Ate 15 segundos em passos de meio segundo; o historico reinicia ao mudar de nivel. Os estados manuais nao mudam."],
        "Rewind history": ["Rewind history", "Cronologia rewind", "Historial de rebobinado", "Historico de rewind"],
        "Timeline help": ["Hover or use arrows to preview. Older on the left, newer on the right. Enter/A confirms; Esc/B cancels.", "Passa sulle immagini o usa le frecce per vedere l'anteprima. Piu vecchie a sinistra, recenti a destra. Invio/A conferma; Esc/B annulla.", "Pasa sobre las imagenes o usa flechas para previsualizar. Anteriores a la izquierda, recientes a la derecha. Intro/A confirma; Esc/B cancela.", "Passe sobre as imagens ou use setas para visualizar. Antigas a esquerda, recentes a direita. Enter/A confirma; Esc/B cancela."],
        "Resume here": ["Resume here", "Riprendi da qui", "Continuar desde aqui", "Continuar daqui"],
        "No rewind history": ["No checkpoints yet. Enable rewind in the quick menu and play for a few seconds.", "Non ci sono ancora stati. Attiva rewind nel menu rapido e gioca per qualche secondo.", "Aun no hay estados. Activa el rebobinado en el menu rapido y juega unos segundos.", "Ainda nao ha estados. Ative o rewind no menu rapido e jogue por alguns segundos."],
        "Loading history": ["Loading previews...", "Caricamento anteprime...", "Cargando imagenes...", "Carregando imagens..."],
        "Restoring checkpoint": ["Restoring selected moment...", "Ripristino del momento selezionato...", "Restaurando el momento seleccionado...", "Restaurando o momento selecionado..."],
        "Checkpoint unavailable": ["Checkpoint unavailable. Cancel and reopen the history.", "Stato non disponibile. Annulla e riapri la cronologia.", "Estado no disponible. Cancela y abre el historial de nuevo.", "Estado indisponivel. Cancele e abra o historico novamente."],
        "Engine": ["Rendering backend", "Motore grafico", "Motor gráfico", "Motor gráfico"],
        "Animated background": ["Animated background", "Sfondo animato", "Fondo animado", "Fundo animado"],
        "Renderer help": ["Metal and OpenGL use the same V2 engine, quick menu and savestates. Changes apply to new sessions; suspended sessions keep their renderer.", "Metal e OpenGL usano lo stesso motore V2, menu rapido e savestate. La scelta vale per le nuove sessioni; quelle sospese conservano il proprio renderer.", "Metal y OpenGL usan el mismo motor V2, menú rápido y estados. Los cambios se aplican a las nuevas sesiones; las suspendidas conservan su renderizador.", "Metal e OpenGL usam o mesmo motor V2, menu rápido e estados. As mudanças valem para novas sessões; as suspensas mantêm seu renderizador."],
        "Quick menu": ["Quick menu", "Menu rapido", "Menú rápido", "Menu rápido"],
        "Resume game": ["Resume game", "Riprendi gioco", "Continuar juego", "Continuar jogo"],
        "Capture in a new slot": ["Capture in a new slot", "Cattura in un nuovo slot", "Guardar en una nueva ranura", "Salvar em um novo slot"],
        "Load selected slot": ["Load selected slot", "Carica lo slot selezionato", "Cargar ranura seleccionada", "Carregar slot selecionado"],
        "Suspend session": ["Suspend session", "Sospendi sessione", "Suspender sesión", "Suspender sessão"],
        "Fullscreen / window": ["Fullscreen / window", "Schermo intero / finestra", "Pantalla completa / ventana", "Tela cheia / janela"],
        "Return to launcher": ["Return to launcher", "Torna al launcher", "Volver al lanzador", "Voltar ao launcher"],
        "Shader: %@": ["Shader: %@", "Shader: %@", "Shader: %@", "Shader: %@"],
        "Save shader for this game": ["Save shader for this game", "Shader default per questo gioco", "Shader predeterminado para este juego", "Shader padrão para este jogo"],
        "Save shader for all games": ["Save shader for all games", "Shader default per tutti i giochi", "Shader predeterminado para todos los juegos", "Shader padrão para todos os jogos"],
        "Use global shader for this game": ["Use global shader for this game", "Usa il default globale per questo gioco", "Usar shader global para este juego", "Usar shader global para este jogo"],
        "Global default": ["Global default", "Default globale", "Predeterminado global", "Padrão global"],
        "Game default": ["Game default", "Default di questo gioco", "Predeterminado de este juego", "Padrão deste jogo"],
        "Session only": ["This session only (not saved)", "Solo questa sessione (non salvato)", "Solo esta sesión (sin guardar)", "Apenas esta sessão (não salvo)"],
        "Shader applied: %@": ["Shader applied: %@. Resume to see the result.", "Shader applicato: %@. Riprendi per vedere il risultato.", "Shader aplicado: %@. Continúa para ver el resultado.", "Shader aplicado: %@. Continue para ver o resultado."],
        "Capture saved: %@": ["Capture saved: %@", "Cattura salvata: %@", "Estado guardado: %@", "Estado salvo: %@"],
        "Game shader saved": ["Shader saved for this game.", "Shader salvato per questo gioco.", "Shader guardado para este juego.", "Shader salvo para este jogo."],
        "Global shader saved": ["Global default saved. Other games keep their individual overrides.", "Default globale salvato. Restano valide le preferenze specifiche degli altri giochi.", "Predeterminado global guardado. Se mantienen las preferencias de los otros juegos.", "Padrão global salvo. As preferências dos outros jogos são mantidas."],
        "Game follows global": ["This game now follows the global default.", "Questo gioco ora segue il default globale.", "Este juego ahora usa el predeterminado global.", "Este jogo agora usa o padrão global."],
        "Paused / live session": ["PAUSED / LIVE SESSION", "PAUSA / SESSIONE LIVE", "PAUSA / SESIÓN EN VIVO", "PAUSA / SESSÃO AO VIVO"],
        "No live slots": ["No live slots available.", "Nessuno slot live disponibile.", "No hay ranuras disponibles.", "Nenhum slot disponível."],
        "Live slot": ["Live slot", "Slot live", "Ranura de estado", "Slot de estado"],
        "Navigation help": ["UP/DOWN  ACTIONS   LEFT/RIGHT  SLOT / SHADER\nENTER/A  CONFIRM   ESC/B  RESUME", "SU/GIU  AZIONI     SX/DX  SLOT / SHADER\nINVIO/A  CONFERMA  ESC/B  RIPRENDI", "ARRIBA/ABAJO  ACCIONES  IZQ/DER  RANURA / SHADER\nINTRO/A  CONFIRMAR      ESC/B  CONTINUAR", "CIMA/BAIXO  AÇÕES  ESQ/DIR  SLOT / SHADER\nENTER/A  CONFIRMAR  ESC/B  CONTINUAR"],
        "Language": ["Language", "Lingua", "Idioma", "Idioma"],
        "Keyboard": ["Keyboard", "Tastiera", "Teclado", "Teclado"],
        "Controller": ["Controller", "Controller", "Mando", "Controle"],
        "Quick menu settings": ["In-game quick menu", "Menu rapido durante il gioco", "Menú rápido durante el juego", "Menu rápido durante o jogo"],
        "Shortcut help": ["Language and shortcuts apply to the launcher and in-game menu. For Mac function keys, use Fn or choose Cmd + Shift + M.", "Lingua e scorciatoie valgono per launcher e menu di gioco. Per i tasti funzione del Mac usa Fn oppure scegli Cmd + Shift + M.", "El idioma y los atajos se aplican al lanzador y al menú del juego. Para las teclas de función de Mac, usa Fn o Cmd + Shift + M.", "O idioma e os atalhos são usados no launcher e no menu do jogo. Para as teclas de função do Mac, use Fn ou Cmd + Shift + M."],
        "Original": ["Original", "Originale", "Original", "Original"],
        "Bilinear": ["Bilinear", "Bilineare", "Bilineal", "Bilinear"],
        "Scanlines": ["Scanlines", "Scanlines", "Scanlines", "Scanlines"],
        "CRT Lite": ["CRT Lite", "CRT leggero", "CRT ligero", "CRT leve"],
        "Library": ["Library", "Libreria", "Biblioteca", "Biblioteca"],
        "Search games": ["Search games", "Cerca giochi", "Buscar juegos", "Buscar jogos"],
        "Launch": ["Launch", "Avvia", "Iniciar", "Iniciar"],
        "Play": ["Play", "Gioca", "Jugar", "Jogar"],
        "Import Cover": ["Import Cover", "Importa copertina", "Importar portada", "Importar capa"],
        "Reveal in Finder": ["Reveal in Finder", "Mostra nel Finder", "Mostrar en Finder", "Mostrar no Finder"],
        "Reveal": ["Reveal", "Mostra", "Mostrar", "Mostrar"],
        "Open Paks": ["Open Paks", "Apri Paks", "Abrir Paks", "Abrir Paks"],
        "Cover art": ["Cover art", "Copertina", "Portada", "Capa"],
        "Cover help": ["Generated automatically and stored in the local cover library database.", "Generata automaticamente e conservata nella libreria locale delle copertine.", "Generada automáticamente y guardada en la biblioteca local de portadas.", "Gerada automaticamente e armazenada na biblioteca local de capas."],
        "Recent Saves": ["Recent Saves", "Salvataggi recenti", "Guardados recientes", "Salvamentos recentes"],
        "No saves yet for this game.": ["No saves yet for this game.", "Nessun salvataggio per questo gioco.", "Todavía no hay guardados para este juego.", "Ainda não há salvamentos para este jogo."],
        "Controls": ["Controls", "Comandi", "Controles", "Controles"],
        "Controls help": ["Open the quick menu with the keyboard or controller shortcut chosen in Settings.", "Apri il menu rapido con la scorciatoia da tastiera o controller scelta nelle Impostazioni.", "Abre el menú rápido con el atajo de teclado o mando elegido en Ajustes.", "Abra o menu rápido com o atalho de teclado ou controle escolhido nas Configurações."],
        "No games in library": ["No games in library", "Nessun gioco in libreria", "No hay juegos en la biblioteca", "Nenhum jogo na biblioteca"],
        "Add games help": ["Use Settings or Open Paks to add .pak files.", "Usa Impostazioni o Apri Paks per aggiungere file .pak.", "Usa Ajustes o Abrir Paks para añadir archivos .pak.", "Use Configurações ou Abrir Paks para adicionar arquivos .pak."],
        "Settings": ["Settings", "Impostazioni", "Ajustes", "Configurações"],
        "Done": ["Done", "Fine", "Listo", "Concluído"],
        "Open": ["Open", "Apri", "Abrir", "Abrir"],
        "Paks": ["Paks", "Paks", "Paks", "Paks"],
        "Saves": ["Saves", "Salvataggi", "Guardados", "Salvamentos"],
        "Logs": ["Logs", "Log", "Registros", "Registros"],
        "ScreenShots": ["Screenshots", "Schermate", "Capturas", "Capturas"],
        "Covers": ["Covers", "Copertine", "Portadas", "Capas"],
        "Video": ["Video", "Video", "Vídeo", "Vídeo"],
        "Video help": ["The stable V2 Metal host is built into this launcher. Choose shaders and per-game defaults in the quick menu.", "Il runtime Metal stabile della V2 è integrato nel launcher. Scegli shader e default per gioco dal menu rapido.", "El runtime Metal estable V2 está integrado en el lanzador. Elige shaders y valores por juego en el menú rápido.", "O runtime Metal estável V2 está integrado no launcher. Escolha shaders e padrões por jogo no menu rápido."],
        "ScreenScraper help": ["Enter API credentials to download covers into the local library.", "Inserisci le credenziali API per scaricare copertine nella libreria locale.", "Introduce credenciales API para descargar portadas en la biblioteca local.", "Insira credenciais API para baixar capas na biblioteca local."],
        "Developer ID": ["Developer ID", "ID sviluppatore", "ID de desarrollador", "ID de desenvolvedor"],
        "Developer Password": ["Developer Password", "Password sviluppatore", "Contraseña de desarrollador", "Senha de desenvolvedor"],
        "User ID (optional)": ["User ID (optional)", "ID utente (opzionale)", "ID de usuario (opcional)", "ID de usuário (opcional)"],
        "User Password (optional)": ["User Password (optional)", "Password utente (opzionale)", "Contraseña de usuario (opcional)", "Senha de usuário (opcional)"],
        "Refresh Covers": ["Refresh Covers", "Aggiorna copertine", "Actualizar portadas", "Atualizar capas"],
        "Online covers enabled": ["Online covers enabled", "Copertine online attive", "Portadas en línea activadas", "Capas online ativadas"],
        "Credentials needed": ["Developer ID and password required", "Servono ID e password sviluppatore", "Se requieren ID y contraseña de desarrollador", "ID e senha de desenvolvedor necessários"],
        "Integration help": ["Launch a game with --launch <pak-path>. The launcher owns the V2 runtime and stays open for resume and savestates.", "Avvia un gioco con --launch <pak-path>. Il launcher gestisce il runtime V2 e resta aperto per ripresa e savestate.", "Inicia un juego con --launch <pak-path>. El lanzador gestiona V2 y permanece abierto para reanudar y cargar estados.", "Inicie um jogo com --launch <pak-path>. O launcher gerencia V2 e permanece aberto para retomar e carregar estados."],
        "New session": ["New session", "Nuova sessione", "Nueva sesión", "Nova sessão"],
        "Resume session": ["Resume session", "Riprendi sessione", "Reanudar sesión", "Retomar sessão"],
        "Resume progress": ["Resume progress", "Riprendi progresso", "Reanudar progreso", "Retomar progresso"],
        "Load disk snapshot": ["Load disk snapshot", "Carica snapshot disco", "Cargar copia de disco", "Carregar snapshot de disco"],
        "Load savestate": ["Load savestate", "Carica savestate", "Cargar estado", "Carregar estado"],
        "Session": ["Session", "Sessione", "Sesión", "Sessão"],
        "No suspended session": ["No suspended live session for this game.", "Nessuna sessione live sospesa per questo gioco.", "No hay una sesión suspendida para este juego.", "Nenhuma sessão suspensa para este jogo."],
        "No savestates": ["Capture a slot from the in-game quick menu first.", "Cattura prima uno slot dal menu rapido durante il gioco.", "Primero guarda un estado desde el menú rápido del juego.", "Primeiro salve um slot pelo menu rápido do jogo."],
        "Ready": ["Ready", "Pronto", "Listo", "Pronto"],
        "Games available": ["%d game(s) available", "%d giochi disponibili", "%d juegos disponibles", "%d jogos disponíveis"],
        "Launching %@": ["Launching %@…", "Avvio di %@…", "Iniciando %@…", "Iniciando %@…"],
        "Choose cover": ["Choose cover for %@", "Scegli copertina per %@", "Elige portada para %@", "Escolha capa para %@"],
        "Cover chooser help": ["Select a PNG, JPG or WEBP image.", "Seleziona un'immagine PNG, JPG o WEBP.", "Selecciona una imagen PNG, JPG o WEBP.", "Selecione uma imagem PNG, JPG ou WEBP."],
        "Cover imported": ["Cover imported for %@", "Copertina importata per %@", "Portada importada para %@", "Capa importada para %@"],
        "Invalid slot": ["The slot has no restorable state.", "Lo slot non contiene uno stato ripristinabile.", "La ranura no contiene un estado restaurable.", "O slot não contém um estado restaurável."],
        "Runtime idle": ["Ready", "Pronto", "Listo", "Pronto"],
        "Runtime running": ["Game running", "Gioco in esecuzione", "Juego en ejecución", "Jogo em execução"],
        "Runtime preparing": ["Preparing game", "Preparazione del gioco", "Preparando juego", "Preparando jogo"],
        "Runtime stopping": ["Stopping game", "Arresto del gioco", "Deteniendo juego", "Encerrando jogo"]
    ]
}
