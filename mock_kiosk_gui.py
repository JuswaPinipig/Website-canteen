#!/usr/bin/env python3
"""
NovaLunch Automated Canteen Kiosk - Mock Student-Facing GUI Terminal
======================================================================
A crash-proof, zero-hardware Pygame interface for NovaLunch.

Features:
- Pure Pygame implementation (NO OpenCV / cv2 dependencies).
- Real-Time Voice/TTS Announcements ("Successfully scanned", "Scanned Adobo & Rice", "Total is ₱115.00").
- 4-State Controller Machine: IDLE -> GREET -> SCANNING -> SETTLEMENT.
- Interactive Voice Testing Suite (Dedicated buttons for testing spoken announcements).
- Split-screen grid layout: Top Header Bar (80px), Left Camera Placeholder Panel (720x540),
  Right Tally Card Panel (500x540), and Footer Bar (40px).
"""

import sys
import time
import shutil
import subprocess
import threading
import numpy as np
import pygame

# ==============================================================================
# CONFIGURATION & COLOR PALETTE
# ==============================================================================
SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
TARGET_FPS = 60

# Branding Color Palette
COLOR_NAVY = (15, 32, 67)         # Deep Navy Blue (#0F2043)
COLOR_GOLD = (245, 180, 26)       # Gold Accent (#F5B41A)
COLOR_GOLD_HOVER = (220, 160, 20) # Gold Hover / Pressed
COLOR_BG_GRAY = (240, 242, 245)   # Off-White Light Gray (#F0F2F5)
COLOR_WHITE = (255, 255, 255)     # Clean White (#FFFFFF)
COLOR_CHARCOAL = (30, 30, 30)     # Dark Charcoal Text (#1E1E1E)
COLOR_GRAY_TEXT = (108, 117, 125) # Muted Text Gray (#6C757D)
COLOR_BTN_DISABLED = (180, 185, 195) # Disabled Button Gray
COLOR_SUCCESS = (40, 167, 69)     # Success Green (#28A745)
COLOR_DANGER = (220, 53, 69)       # Alert Red (#DC3545)
COLOR_BORDER = (200, 200, 200)     # Border Gray (#C8C8C8)
COLOR_GRID_LINE = (225, 228, 233)  # Grid Line Gray

# State Constants
STATE_IDLE = 1
STATE_GREET = 2
STATE_SCANNING = 3
STATE_SETTLEMENT = 4

# Mock Student Data
MOCK_STUDENT = {
    "name": "Adi",
    "balance": 150.00
}

# Mock Scanned Food Items (Adobo & Rice requested)
MOCK_ITEMS = [
    {"name": "Pork Adobo", "qty": 1, "price": 100.00},
    {"name": "Steamed Rice", "qty": 1, "price": 15.00}
]

# ==============================================================================
# VOICE ANNOUNCEMENT & TTS ENGINE
# ==============================================================================
def speak_text(text):
    """
    Non-blocking Text-to-Speech (TTS) announcement thread.
    Speaks out loud without freezing or delaying the Pygame render pipeline.
    """
    def _run_tts():
        try:
            if shutil.which("say"):
                # Use macOS native high-quality speech engine
                subprocess.run(["say", "-v", "Samantha", text], check=False)
            else:
                print(f"[VOICE ANNOUNCEMENT]: {text}")
        except Exception as e:
            print(f"[VOICE WARN] Speech error: {e}")

    threading.Thread(target=_run_tts, daemon=True).start()

def create_synthesized_chime():
    """Generates a pleasant payment chime sound effect."""
    try:
        pygame.mixer.init(frequency=44100, size=-16, channels=2, buffer=512)
        sample_rate = 44100
        duration = 0.35
        t = np.linspace(0, duration, int(sample_rate * duration), False)
        w1 = np.sin(2 * np.pi * 523.25 * t) * 0.3
        w2 = np.sin(2 * np.pi * 659.25 * t) * 0.3
        w3 = np.sin(2 * np.pi * 783.99 * t) * 0.3
        envelope = np.exp(-4.0 * t)
        sound_array = ((w1 + w2 + w3) * envelope * 32767).astype(np.int16)
        stereo_array = np.column_stack((sound_array, sound_array))
        return pygame.sndarray.make_sound(stereo_array)
    except Exception as e:
        print(f"[AUDIO INFO] Synthesizer warning: {e}")
        return None

# ==============================================================================
# MOCK KIOSK GUI CLASS
# ==============================================================================
class MockNovaLunchKioskGUI:
    def __init__(self):
        pygame.init()
        pygame.font.init()
        pygame.display.set_caption("NovaLunch Terminal #01 — Mock Student Canteen Kiosk")

        self.screen = pygame.display.set_mode((SCREEN_WIDTH, SCREEN_HEIGHT))
        self.clock = pygame.time.Clock()

        # Fonts
        self.font_title = pygame.font.SysFont("Helvetica", 24, bold=True)
        self.font_subtitle = pygame.font.SysFont("Helvetica", 14)
        self.font_header = pygame.font.SysFont("Helvetica", 20, bold=True)
        self.font_body = pygame.font.SysFont("Helvetica", 16)
        self.font_body_bold = pygame.font.SysFont("Helvetica", 16, bold=True)
        self.font_placeholder = pygame.font.SysFont("Helvetica", 22, bold=True)
        self.font_large = pygame.font.SysFont("Helvetica", 32, bold=True)
        self.font_footer = pygame.font.SysFont("Helvetica", 15)

        # Controller State Variables
        self.current_state = STATE_IDLE
        self.active_student = None
        self.cart_items = []
        self.total_amount = 0.0
        self.state_timer = 0.0
        self.status_message = "Welcome to NovaLunch! Please tap your Student ID Card to begin."

        # Audio Sound Effects
        self.chime_sound = create_synthesized_chime()

        # Interactive UI Rectangles
        self.action_button_rect = pygame.Rect(780, 565, 460, 55)
        
        # Voice Testing Toolbar Buttons (Bottom of Left Panel)
        self.btn_voice_scan = pygame.Rect(35, 575, 160, 45)
        self.btn_voice_items = pygame.Rect(205, 575, 175, 45)
        self.btn_voice_total = pygame.Rect(390, 575, 150, 45)
        self.btn_voice_full = pygame.Rect(550, 575, 170, 45)

    # --------------------------------------------------------------------------
    # VOICE ANNOUNCEMENT TRIGGER HELPERS
    # --------------------------------------------------------------------------
    def trigger_voice_announcement(self, voice_type):
        """Triggers spoken voice announcements out loud."""
        if voice_type == "scanned":
            msg = "Successfully scanned!"
        elif voice_type == "items":
            msg = "Scanned Pork Adobo and Steamed Rice."
        elif voice_type == "total":
            msg = "Total is 115 pesos."
        elif voice_type == "full":
            msg = "Successfully scanned Pork Adobo and Steamed Rice. Total is 115 pesos."
        elif voice_type == "payment":
            msg = "Payment successful! Remaining balance is 35 pesos."
        else:
            msg = str(voice_type)

        print(f"[VOICE MOCK TEST]: {msg}")
        self.status_message = f"VOICE ANNOUNCEMENT: '{msg}'"
        speak_text(msg)

    # --------------------------------------------------------------------------
    # STATE MACHINE CONTROLLER LOGIC
    # --------------------------------------------------------------------------
    def transition_to_state(self, new_state):
        self.current_state = new_state
        self.state_timer = time.time()

        if new_state == STATE_IDLE:
            self.active_student = None
            self.cart_items = []
            self.total_amount = 0.0
            self.status_message = "Welcome to NovaLunch! Please tap your Student ID Card to begin."

        elif new_state == STATE_GREET:
            self.active_student = dict(MOCK_STUDENT)
            self.cart_items = []
            self.total_amount = 0.0
            self.status_message = f"Hello {self.active_student['name']}! Please place items on the tray."
            speak_text("Welcome Adi! Please place items on the tray.")

        elif new_state == STATE_SCANNING:
            self.cart_items = list(MOCK_ITEMS)
            self.total_amount = sum(item["price"] * item["qty"] for item in self.cart_items)
            self.status_message = f"Items detected! Tap ID Card again to confirm & pay ₱{self.total_amount:.2f}."
            
            # Real-time Voice Announcement as requested: "Successfully scanned, scanned Adobo, Rice, Total is 115"
            speak_text("Successfully scanned Pork Adobo and Steamed Rice. Total is 115 pesos.")

        elif new_state == STATE_SETTLEMENT:
            rem_balance = self.active_student["balance"] - self.total_amount
            self.active_student["balance"] = rem_balance
            self.status_message = f"Payment Successful! Remaining Balance: ₱{rem_balance:.2f}"
            
            if self.chime_sound:
                try:
                    self.chime_sound.play()
                except Exception:
                    pass
            
            speak_text("Payment successful! Remaining balance: 35 pesos. Thank you!")

    def handle_rfid_tap(self):
        """Simulates RFID card tap or Gold Action Button press."""
        if self.current_state == STATE_IDLE:
            self.transition_to_state(STATE_GREET)
        elif self.current_state == STATE_SCANNING:
            self.transition_to_state(STATE_SETTLEMENT)
        elif self.current_state == STATE_SETTLEMENT:
            self.transition_to_state(STATE_IDLE)

    # --------------------------------------------------------------------------
    # RENDER PIPELINE COMPONENTS
    # --------------------------------------------------------------------------
    def render_header(self):
        """Top Header Bar (Height: 80px)."""
        pygame.draw.rect(self.screen, COLOR_NAVY, (0, 0, SCREEN_WIDTH, 80))
        pygame.draw.rect(self.screen, COLOR_GOLD, (0, 77, SCREEN_WIDTH, 3))

        title_surf = self.font_title.render("NovaLunch Terminal #01", True, COLOR_WHITE)
        sub_surf = self.font_subtitle.render("Automated Student Canteen Kiosk", True, COLOR_GOLD)
        self.screen.blit(title_surf, (25, 16))
        self.screen.blit(sub_surf, (25, 48))

        if self.active_student and self.current_state != STATE_IDLE:
            student_name = self.active_student["name"]
            balance_val = self.active_student["balance"]

            info_text = f"{student_name} | Balance: ₱{balance_val:.2f}"
            info_surf = self.font_header.render(info_text, True, COLOR_WHITE)
            self.screen.blit(info_surf, (SCREEN_WIDTH - info_surf.get_width() - 25, 28))
        else:
            idle_surf = self.font_body.render("Tap Student ID to Begin", True, COLOR_GOLD)
            self.screen.blit(idle_surf, (SCREEN_WIDTH - idle_surf.get_width() - 25, 30))

    def render_left_panel(self):
        """Left Panel (60% Width, 720x540 Container at x=20, y=100)."""
        panel_rect = pygame.Rect(20, 100, 720, 540)
        pygame.draw.rect(self.screen, COLOR_WHITE, panel_rect, border_radius=8)
        pygame.draw.rect(self.screen, COLOR_BORDER, panel_rect, width=2, border_radius=8)

        card_title = self.font_header.render("LIVE TRAY CAMERA FEED", True, COLOR_NAVY)
        self.screen.blit(card_title, (40, 115))

        # Inner Placeholder Box Area (700x400 at x=30, y=150)
        placeholder_area = pygame.Rect(30, 150, 700, 400)
        pygame.draw.rect(self.screen, COLOR_BG_GRAY, placeholder_area, border_radius=4)
        pygame.draw.rect(self.screen, COLOR_BORDER, placeholder_area, width=1, border_radius=4)

        # Background Grid
        for x in range(placeholder_area.left, placeholder_area.right, 40):
            pygame.draw.line(self.screen, COLOR_GRID_LINE, (x, placeholder_area.top), (x, placeholder_area.bottom), 1)
        for y in range(placeholder_area.top, placeholder_area.bottom, 40):
            pygame.draw.line(self.screen, COLOR_GRID_LINE, (placeholder_area.left, y), (placeholder_area.right, y), 1)

        # Dynamic Placeholder Text according to State
        if self.current_state == STATE_IDLE:
            text_str = "[ CAMERA STANDBY ]"
            text_color = COLOR_CHARCOAL
        elif self.current_state == STATE_GREET:
            text_str = "[ LIVE CAMERA FEED PLACEHOLDER ]"
            text_color = COLOR_NAVY
        elif self.current_state == STATE_SCANNING:
            text_str = "[ SCANNING TRAY: ADOBO + RICE DETECTED ]"
            text_color = COLOR_SUCCESS
        elif self.current_state == STATE_SETTLEMENT:
            text_str = "[ PAYMENT APPROVED — TRAY CHECKOUT COMPLETE ]"
            text_color = COLOR_SUCCESS

        text_surf = self.font_placeholder.render(text_str, True, text_color)
        cx = placeholder_area.centerx - text_surf.get_width() // 2
        cy = placeholder_area.centery - text_surf.get_height() // 2
        self.screen.blit(text_surf, (cx, cy))

        # Render Interactive Voice Testing Toolbar
        self.render_voice_test_toolbar()

    def render_voice_test_toolbar(self):
        """Render 4 Voice Announcement Testing Buttons inside Left Panel."""
        mouse_pos = pygame.mouse.get_pos()

        btn_configs = [
            (self.btn_voice_scan, "Scanned!", "🗣️", COLOR_NAVY, "[1]"),
            (self.btn_voice_items, "Adobo & Rice", "🍱", COLOR_NAVY, "[2]"),
            (self.btn_voice_total, "Total ₱115", "💰", COLOR_NAVY, "[3]"),
            (self.btn_voice_full, "Full Voice Test", "🔊", COLOR_GOLD, "[4]")
        ]

        for rect, label, icon, bg_color, key_hint in btn_configs:
            is_hovered = rect.collidepoint(mouse_pos)
            fill_color = COLOR_GOLD_HOVER if (is_hovered and bg_color == COLOR_GOLD) else ((30, 50, 90) if is_hovered else bg_color)
            
            pygame.draw.rect(self.screen, fill_color, rect, border_radius=6)
            if is_hovered:
                pygame.draw.rect(self.screen, COLOR_GOLD, rect, width=2, border_radius=6)

            btn_str = f"{icon} {label} {key_hint}"
            text_color = COLOR_NAVY if bg_color == COLOR_GOLD else COLOR_WHITE
            text_surf = self.font_subtitle.render(btn_str, True, text_color)
            
            tx = rect.x + (rect.width - text_surf.get_width()) // 2
            ty = rect.y + (rect.height - text_surf.get_height()) // 2
            self.screen.blit(text_surf, (tx, ty))

    def render_right_panel(self):
        """Right Panel (40% Width, 500x540 Card Container at x=760, y=100)."""
        panel_rect = pygame.Rect(760, 100, 500, 540)
        pygame.draw.rect(self.screen, COLOR_WHITE, panel_rect, border_radius=8)
        pygame.draw.rect(self.screen, COLOR_BORDER, panel_rect, width=2, border_radius=8)

        tally_title = self.font_header.render("RUNNING TALLY", True, COLOR_NAVY)
        self.screen.blit(tally_title, (785, 115))

        pygame.draw.line(self.screen, COLOR_BORDER, (785, 150), (1235, 150), 1)
        h_item = self.font_subtitle.render("ITEM", True, COLOR_GRAY_TEXT)
        h_qty = self.font_subtitle.render("QTY", True, COLOR_GRAY_TEXT)
        h_price = self.font_subtitle.render("PRICE", True, COLOR_GRAY_TEXT)
        
        self.screen.blit(h_item, (785, 158))
        self.screen.blit(h_qty, (1060, 158))
        self.screen.blit(h_price, (1160, 158))
        pygame.draw.line(self.screen, COLOR_BORDER, (785, 180), (1235, 180), 1)

        if self.current_state in [STATE_IDLE, STATE_GREET] or not self.cart_items:
            empty_surf = self.font_body.render("No items scanned yet.", True, COLOR_GRAY_TEXT)
            self.screen.blit(empty_surf, (760 + (500 - empty_surf.get_width()) // 2, 280))
        else:
            start_y = 195
            for idx, item in enumerate(self.cart_items):
                row_y = start_y + (idx * 40)
                if idx % 2 == 0:
                    pygame.draw.rect(self.screen, COLOR_BG_GRAY, (785, row_y - 4, 450, 34), border_radius=4)
                
                i_name = self.font_body_bold.render(item["name"], True, COLOR_CHARCOAL)
                i_qty = self.font_body.render(f"x{item['qty']}", True, COLOR_CHARCOAL)
                i_price = self.font_body_bold.render(f"₱{item['price'] * item['qty']:.2f}", True, COLOR_NAVY)

                self.screen.blit(i_name, (795, row_y + 2))
                self.screen.blit(i_qty, (1065, row_y + 2))
                self.screen.blit(i_price, (1160, row_y + 2))

        pygame.draw.line(self.screen, COLOR_BORDER, (785, 470), (1235, 470), 2)

        total_lbl = self.font_header.render("TOTAL:", True, COLOR_CHARCOAL)
        total_val = self.font_large.render(f"₱{self.total_amount:.2f}", True, COLOR_NAVY)
        
        self.screen.blit(total_lbl, (785, 495))
        self.screen.blit(total_val, (1235 - total_val.get_width(), 488))

        self.render_action_button()

    def render_action_button(self):
        btn_rect = self.action_button_rect
        mouse_pos = pygame.mouse.get_pos()
        is_hovered = btn_rect.collidepoint(mouse_pos)

        if self.current_state == STATE_IDLE:
            btn_bg = COLOR_BTN_DISABLED
            btn_text = "Awaiting Student ID..."
            text_color = COLOR_WHITE
        elif self.current_state == STATE_GREET:
            btn_bg = COLOR_GOLD
            btn_text = "Initializing Scanner..."
            text_color = COLOR_NAVY
        elif self.current_state == STATE_SCANNING:
            btn_bg = COLOR_GOLD_HOVER if is_hovered else COLOR_GOLD
            btn_text = f"Tap ID Card Again to Confirm & Pay ₱{self.total_amount:.2f}"
            text_color = COLOR_NAVY
        elif self.current_state == STATE_SETTLEMENT:
            btn_bg = COLOR_SUCCESS
            btn_text = "✓ Payment Approved — Resetting..."
            text_color = COLOR_WHITE

        pygame.draw.rect(self.screen, btn_bg, btn_rect, border_radius=8)
        if is_hovered and self.current_state == STATE_SCANNING:
            pygame.draw.rect(self.screen, COLOR_NAVY, btn_rect, width=2, border_radius=8)

        text_surf = self.font_body_bold.render(btn_text, True, text_color)
        tx = btn_rect.x + (btn_rect.width - text_surf.get_width()) // 2
        ty = btn_rect.y + (btn_rect.height - text_surf.get_height()) // 2
        self.screen.blit(text_surf, (tx, ty))

    def render_footer(self):
        footer_rect = pygame.Rect(0, 680, SCREEN_WIDTH, 40)
        pygame.draw.rect(self.screen, COLOR_NAVY, footer_rect)
        pygame.draw.rect(self.screen, COLOR_GOLD, (0, 680, SCREEN_WIDTH, 2))

        msg_surf = self.font_footer.render(f"STATUS: {self.status_message}", True, COLOR_WHITE)
        self.screen.blit(msg_surf, (25, 690))

        hints_surf = self.font_subtitle.render("[SPACE: Tap ID | 1/2/3/4: Spoken Voice Tests | R: Reset]", True, COLOR_GOLD)
        self.screen.blit(hints_surf, (SCREEN_WIDTH - hints_surf.get_width() - 25, 692))

    # --------------------------------------------------------------------------
    # MAIN APPLICATION LOOP
    # --------------------------------------------------------------------------
    def run(self):
        running = True
        print("=============================================================")
        print("   NOVALUNCH MOCK KIOSK GUI TERMINAL INITIALIZED             ")
        print("=============================================================")
        print("  Controls & Keybindings:")
        print("  - [SPACEBAR] : Advance State Machine / Tap Student ID")
        print("  - [1]        : Speak 'Successfully scanned!'")
        print("  - [2]        : Speak 'Scanned Pork Adobo and Steamed Rice'")
        print("  - [3]        : Speak 'Total is 115 pesos'")
        print("  - [4]        : Speak Full Scan Announcement")
        print("  - [R]        : Reset System to STATE_IDLE")
        print("=============================================================")

        while running:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False

                elif event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_ESCAPE:
                        running = False
                    elif event.key == pygame.K_SPACE:
                        self.handle_rfid_tap()
                    elif event.key == pygame.K_r:
                        self.transition_to_state(STATE_IDLE)
                    elif event.key in [pygame.K_1, pygame.K_KP1]:
                        self.trigger_voice_announcement("scanned")
                    elif event.key in [pygame.K_2, pygame.K_KP2]:
                        self.trigger_voice_announcement("items")
                    elif event.key in [pygame.K_3, pygame.K_KP3]:
                        self.trigger_voice_announcement("total")
                    elif event.key in [pygame.K_4, pygame.K_KP4]:
                        self.trigger_voice_announcement("full")

                elif event.type == pygame.MOUSEBUTTONDOWN:
                    if event.button == 1:
                        pos = event.pos
                        if self.action_button_rect.collidepoint(pos):
                            self.handle_rfid_tap()
                        elif self.btn_voice_scan.collidepoint(pos):
                            self.trigger_voice_announcement("scanned")
                        elif self.btn_voice_items.collidepoint(pos):
                            self.trigger_voice_announcement("items")
                        elif self.btn_voice_total.collidepoint(pos):
                            self.trigger_voice_announcement("total")
                        elif self.btn_voice_full.collidepoint(pos):
                            self.trigger_voice_announcement("full")

            now = time.time()
            if self.current_state == STATE_GREET:
                if now - self.state_timer >= 1.5:
                    self.transition_to_state(STATE_SCANNING)

            elif self.current_state == STATE_SETTLEMENT:
                if now - self.state_timer >= 3.0:
                    self.transition_to_state(STATE_IDLE)

            self.screen.fill(COLOR_BG_GRAY)

            self.render_header()
            self.render_left_panel()
            self.render_right_panel()
            self.render_footer()

            pygame.display.flip()
            self.clock.tick(TARGET_FPS)

        pygame.quit()
        sys.exit(0)

# ==============================================================================
# ENTRY POINT
# ==============================================================================
if __name__ == "__main__":
    app = MockNovaLunchKioskGUI()
    app.run()
