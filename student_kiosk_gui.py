#!/usr/bin/env python3
"""
NovaLunch Automated Canteen Kiosk - Student-Facing Display GUI
================================================================
A crash-proof, multi-threaded Pygame & OpenCV interface for NovaLunch.

Features:
- Non-blocking camera frame capture thread with auto-fallback standby graphics.
- 4-State Controller: IDLE -> GREET -> SCANNING -> SETTLEMENT.
- Spoken Voice/TTS Announcements ("Successfully scanned", "Pork Adobo", "Steamed Rice", "Total ₱115.00").
- Interactive Voice & Audio Diagnostic Suite.
"""

import sys
import time
import math
import shutil
import subprocess
import threading
import numpy as np
import cv2
import pygame

# ==============================================================================
# CONFIGURATION & COLOR PALETTE
# ==============================================================================
SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
TARGET_FPS = 60

# Brand Colors
COLOR_NAVY = (15, 32, 67)       # Deep Navy Blue (#0F2043)
COLOR_GOLD = (245, 180, 26)     # Gold Accent (#F5B41A)
COLOR_GOLD_HOVER = (220, 160, 20)# Darker Gold for hover/pressed
COLOR_BG_GRAY = (240, 242, 245) # Off-White Light Gray (#F0F2F5)
COLOR_WHITE = (255, 255, 255)   # Clean White (#FFFFFF)
COLOR_CHARCOAL = (30, 30, 30)   # Dark Charcoal Text (#1E1E1E)
COLOR_GRAY_TEXT = (100, 105, 115) # Muted Text Gray
COLOR_SUCCESS = (40, 167, 69)   # Success Green (#28A745)
COLOR_DANGER = (220, 53, 69)     # Alert Red (#DC3545)
COLOR_BORDER = (200, 200, 200)   # Border Gray (#C8C8C8)
COLOR_GRID_LINE = (225, 228, 233)# Standby grid line color

# State Constants
STATE_IDLE = 1
STATE_GREET = 2
STATE_SCANNING = 3
STATE_SETTLEMENT = 4

# Mock Student Profiles
DEMO_STUDENT = {
    "name": "Adi Nonog",
    "id": "RFID-883921",
    "balance": 150.00
}

# Mock Scanned Food Items (Adobo & Rice requested)
DEMO_ITEMS = [
    {"name": "Pork Adobo", "qty": 1, "price": 100.00, "bbox": [80, 80, 240, 200], "conf": 0.96},
    {"name": "Steamed Rice", "qty": 1, "price": 15.00, "bbox": [360, 140, 220, 180], "conf": 0.92}
]

# ==============================================================================
# THREADED CAMERA CAPTURE MANAGER
# ==============================================================================
class CameraThread(threading.Thread):
    def __init__(self, camera_index=0):
        super().__init__()
        self.daemon = True
        self.camera_index = camera_index
        self.cap = None
        self.current_frame = None
        self.lock = threading.Lock()
        self.running = True
        self.is_connected = False
        self.force_disabled = False

    def run(self):
        try:
            self.cap = cv2.VideoCapture(self.camera_index)
            if self.cap.isOpened():
                self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
                self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
                self.is_connected = True
        except Exception as e:
            print(f"[CAMERA THREAD] Hardware video init warning: {e}")
            self.is_connected = False

        while self.running:
            if self.force_disabled or not self.is_connected or self.cap is None:
                time.sleep(0.05)
                continue

            try:
                ret, frame = self.cap.read()
                if ret and frame is not None:
                    rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                    with self.lock:
                        self.current_frame = rgb_frame
                else:
                    with self.lock:
                        self.current_frame = None
                    self.is_connected = False
            except Exception as e:
                print(f"[CAMERA THREAD] Frame read error: {e}")
                with self.lock:
                    self.current_frame = None
                time.sleep(0.1)

            time.sleep(0.015)

    def get_frame(self):
        if self.force_disabled:
            return None
        with self.lock:
            return self.current_frame.copy() if self.current_frame is not None else None

    def toggle_manual(self):
        self.force_disabled = not self.force_disabled
        return not self.force_disabled

    def stop(self):
        self.running = False
        if self.cap and self.cap.isOpened():
            self.cap.release()

# ==============================================================================
# VOICE ANNOUNCEMENT & SOUND SYNTHESIZER ENGINE
# ==============================================================================
def speak_text(text):
    """Non-blocking spoken Text-to-Speech (TTS) announcement thread."""
    def _run_tts():
        try:
            if shutil.which("say"):
                subprocess.run(["say", "-v", "Samantha", text], check=False)
            else:
                print(f"[VOICE ANNOUNCEMENT]: {text}")
        except Exception as e:
            print(f"[VOICE WARN] Speech error: {e}")

    threading.Thread(target=_run_tts, daemon=True).start()

def create_synthesized_sounds():
    """Generates synthesized audio effects in memory."""
    sounds = {"success": None, "error": None, "rfid": None}
    try:
        pygame.mixer.init(frequency=44100, size=-16, channels=2, buffer=512)
        sample_rate = 44100
        dur_s = 0.35
        t_s = np.linspace(0, dur_s, int(sample_rate * dur_s), False)
        w1 = np.sin(2 * np.pi * 523.25 * t_s) * 0.3
        w2 = np.sin(2 * np.pi * 659.25 * t_s) * 0.3
        w3 = np.sin(2 * np.pi * 783.99 * t_s) * 0.3
        env_s = np.exp(-4.0 * t_s)
        arr_s = ((w1 + w2 + w3) * env_s * 32767).astype(np.int16)
        sounds["success"] = pygame.sndarray.make_sound(np.column_stack((arr_s, arr_s)))
    except Exception as e:
        print(f"[AUDIO WARN] Audio synthesizer warning: {e}")
    return sounds

# ==============================================================================
# NOVALUNCH MAIN KIOSK APPLICATION
# ==============================================================================
class NovaLunchKioskGUI:
    def __init__(self):
        pygame.init()
        pygame.font.init()
        pygame.display.set_caption("NovaLunch Terminal #01 — Automated Student Canteen Kiosk")

        self.screen = pygame.display.set_mode((SCREEN_WIDTH, SCREEN_HEIGHT))
        self.clock = pygame.time.Clock()

        # Fonts
        self.font_title = pygame.font.SysFont("Helvetica", 24, bold=True)
        self.font_subtitle = pygame.font.SysFont("Helvetica", 14)
        self.font_header = pygame.font.SysFont("Helvetica", 20, bold=True)
        self.font_body = pygame.font.SysFont("Helvetica", 16)
        self.font_body_bold = pygame.font.SysFont("Helvetica", 16, bold=True)
        self.font_large = pygame.font.SysFont("Helvetica", 32, bold=True)
        self.font_footer = pygame.font.SysFont("Helvetica", 15)

        # State Machine Initialization
        self.current_state = STATE_IDLE
        self.active_student = None
        self.cart_items = []
        self.total_amount = 0.0
        self.state_timer = 0.0
        self.insufficient_balance_mode = False
        self.status_message = "Welcome to NovaLunch! Please tap your Student ID Card to begin."

        # Threaded Camera Manager
        self.camera_thread = CameraThread(camera_index=0)
        self.camera_thread.start()

        # Audio Sound Effects
        self.sounds = create_synthesized_sounds()

        # Interactive UI Rectangles
        self.action_button_rect = pygame.Rect(780, 565, 460, 55)
        
        # Voice Testing Toolbar Buttons
        self.btn_voice_scan = pygame.Rect(35, 575, 160, 45)
        self.btn_voice_items = pygame.Rect(205, 575, 175, 45)
        self.btn_voice_total = pygame.Rect(390, 575, 150, 45)
        self.btn_voice_full = pygame.Rect(550, 575, 170, 45)

    def trigger_voice_announcement(self, voice_type):
        if voice_type == "scanned":
            msg = "Successfully scanned!"
        elif voice_type == "items":
            msg = "Scanned Pork Adobo and Steamed Rice."
        elif voice_type == "total":
            msg = "Total is 115 pesos."
        elif voice_type == "full":
            msg = "Successfully scanned Pork Adobo and Steamed Rice. Total is 115 pesos."
        else:
            msg = str(voice_type)

        print(f"[VOICE TEST]: {msg}")
        self.status_message = f"VOICE ANNOUNCEMENT: '{msg}'"
        speak_text(msg)

    def transition_to_state(self, new_state):
        self.current_state = new_state
        self.state_timer = time.time()

        if new_state == STATE_IDLE:
            self.active_student = None
            self.cart_items = []
            self.total_amount = 0.0
            self.status_message = "Welcome to NovaLunch! Please tap your Student ID Card to begin."

        elif new_state == STATE_GREET:
            self.active_student = dict(DEMO_STUDENT)
            if self.insufficient_balance_mode:
                self.active_student["balance"] = 50.00
            self.cart_items = []
            self.total_amount = 0.0
            self.status_message = f"Hello {self.active_student['name']}! Please place items on the tray."
            speak_text(f"Welcome {self.active_student['name']}! Please place items on the tray.")

        elif new_state == STATE_SCANNING:
            self.cart_items = list(DEMO_ITEMS)
            self.total_amount = sum(item["price"] * item["qty"] for item in self.cart_items)
            self.status_message = f"Items detected! Tap ID Card again to confirm & pay ₱{self.total_amount:.2f}."
            speak_text("Successfully scanned Pork Adobo and Steamed Rice. Total is 115 pesos.")

        elif new_state == STATE_SETTLEMENT:
            student_bal = self.active_student["balance"] if self.active_student else 0.0
            if student_bal >= self.total_amount:
                rem_balance = student_bal - self.total_amount
                self.active_student["balance"] = rem_balance
                self.status_message = f"Payment Successful! Remaining Balance: ₱{rem_balance:.2f}"
                if self.sounds.get("success"):
                    try:
                        self.sounds["success"].play()
                    except Exception:
                        pass
                speak_text("Payment successful! Remaining balance: 35 pesos. Thank you!")
            else:
                self.status_message = "Insufficient Funds! Cashier POS override required."
                speak_text("Warning! Insufficient balance. Cashier POS override required.")

    def handle_rfid_tap(self):
        if self.current_state == STATE_IDLE:
            self.transition_to_state(STATE_GREET)
        elif self.current_state == STATE_SCANNING:
            self.transition_to_state(STATE_SETTLEMENT)
        elif self.current_state == STATE_SETTLEMENT:
            self.transition_to_state(STATE_IDLE)

    def render_header(self):
        pygame.draw.rect(self.screen, COLOR_NAVY, (0, 0, SCREEN_WIDTH, 80))
        pygame.draw.rect(self.screen, COLOR_GOLD, (0, 77, SCREEN_WIDTH, 3))

        title_surf = self.font_title.render("NovaLunch Terminal #01", True, COLOR_WHITE)
        sub_surf = self.font_subtitle.render("Automated Student Canteen Checkout System", True, COLOR_GOLD)
        self.screen.blit(title_surf, (25, 16))
        self.screen.blit(sub_surf, (25, 48))

        if self.active_student and self.current_state != STATE_IDLE:
            student_name = self.active_student["name"]
            balance_val = self.active_student["balance"]
            
            name_text = f"Student: {student_name}"
            name_surf = self.font_header.render(name_text, True, COLOR_WHITE)
            self.screen.blit(name_surf, (SCREEN_WIDTH - name_surf.get_width() - 25, 18))

            bal_color = COLOR_SUCCESS if balance_val >= self.total_amount else COLOR_DANGER
            bal_text = f"Balance: ₱{balance_val:.2f}"
            bal_surf = self.font_body_bold.render(bal_text, True, bal_color)
            self.screen.blit(bal_surf, (SCREEN_WIDTH - bal_surf.get_width() - 25, 48))
        else:
            idle_tag = self.font_body.render("Status: Ready | Tap RFID to Begin", True, COLOR_GOLD)
            self.screen.blit(idle_tag, (SCREEN_WIDTH - idle_tag.get_width() - 25, 30))

    def render_left_panel(self):
        panel_rect = pygame.Rect(20, 100, 720, 540)
        pygame.draw.rect(self.screen, COLOR_WHITE, panel_rect, border_radius=8)
        pygame.draw.rect(self.screen, COLOR_BORDER, panel_rect, width=2, border_radius=8)

        header_surf = self.font_header.render("LIVE TRAY AI SCANNER", True, COLOR_NAVY)
        self.screen.blit(header_surf, (40, 115))

        is_cam_active = (self.current_state in [STATE_GREET, STATE_SCANNING, STATE_SETTLEMENT])
        cam_frame = self.camera_thread.get_frame() if is_cam_active else None

        if is_cam_active and cam_frame is not None:
            badge_color = COLOR_SUCCESS
            badge_text = "CAMERA LIVE"
        else:
            badge_color = COLOR_GOLD
            badge_text = "STANDBY MODE"

        pygame.draw.circle(self.screen, badge_color, (630, 127), 6)
        badge_surf = self.font_subtitle.render(badge_text, True, COLOR_CHARCOAL)
        self.screen.blit(badge_surf, (642, 120))

        video_area = pygame.Rect(30, 150, 700, 400)

        if is_cam_active and cam_frame is not None:
            try:
                resized_frame = cv2.resize(cam_frame, (700, 400))
                frame_surface = pygame.surfarray.make_surface(resized_frame.swapaxes(0, 1))
                self.screen.blit(frame_surface, (30, 150))

                if self.current_state in [STATE_SCANNING, STATE_SETTLEMENT]:
                    for item in self.cart_items:
                        bx, by, bw, bh = item["bbox"]
                        rect_x = 30 + bx
                        rect_y = 150 + by
                        box_rect = pygame.Rect(rect_x, rect_y, bw, bh)
                        pygame.draw.rect(self.screen, COLOR_GOLD, box_rect, width=3, border_radius=4)
                        
                        label_str = f"{item['name']} ({int(item['conf']*100)}%) — ₱{item['price']:.2f}"
                        label_surf = self.font_subtitle.render(label_str, True, COLOR_WHITE)
                        bg_label_rect = pygame.Rect(rect_x, rect_y - 24, label_surf.get_width() + 12, 24)
                        pygame.draw.rect(self.screen, COLOR_NAVY, bg_label_rect, border_top_left_radius=4, border_top_right_radius=4)
                        self.screen.blit(label_surf, (rect_x + 6, rect_y - 20))
            except Exception:
                self.render_camera_fallback(video_area)
        else:
            self.render_camera_fallback(video_area)

        pygame.draw.rect(self.screen, COLOR_BORDER, video_area, width=1)
        self.render_voice_test_toolbar()

    def render_camera_fallback(self, area_rect):
        pygame.draw.rect(self.screen, COLOR_BG_GRAY, area_rect)

        for x in range(area_rect.left, area_rect.right, 40):
            pygame.draw.line(self.screen, COLOR_GRID_LINE, (x, area_rect.top), (x, area_rect.bottom), 1)
        for y in range(area_rect.top, area_rect.bottom, 40):
            pygame.draw.line(self.screen, COLOR_GRID_LINE, (area_rect.left, y), (area_rect.right, y), 1)

        cx, cy = area_rect.centerx, area_rect.centery - 20
        pygame.draw.circle(self.screen, COLOR_WHITE, (cx, cy), 45)
        pygame.draw.circle(self.screen, COLOR_NAVY, (cx, cy), 45, width=3)
        pygame.draw.circle(self.screen, COLOR_NAVY, (cx, cy), 20, width=4)
        pygame.draw.circle(self.screen, COLOR_GOLD, (cx + 8, cy - 8), 5)

        main_text = self.font_body_bold.render("Camera Standby — Manual Mode Ready", True, COLOR_NAVY)
        sub_text = self.font_subtitle.render("Tap Student RFID Card or press SPACEBAR to initiate scan sequence", True, COLOR_GRAY_TEXT)
        
        self.screen.blit(main_text, (cx - main_text.get_width() // 2, cy + 65))
        self.screen.blit(sub_text, (cx - sub_text.get_width() // 2, cy + 95))

    def render_voice_test_toolbar(self):
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
        panel_rect = pygame.Rect(760, 100, 500, 540)
        pygame.draw.rect(self.screen, COLOR_WHITE, panel_rect, border_radius=8)
        pygame.draw.rect(self.screen, COLOR_BORDER, panel_rect, width=2, border_radius=8)

        title_surf = self.font_header.render("RUNNING TALLY", True, COLOR_NAVY)
        subtitle_surf = self.font_subtitle.render("Scanned Items & Breakdown", True, COLOR_GRAY_TEXT)
        self.screen.blit(title_surf, (785, 115))
        self.screen.blit(subtitle_surf, (785, 140))

        pygame.draw.line(self.screen, COLOR_BORDER, (785, 165), (1235, 165), 1)
        h_item = self.font_subtitle.render("ITEM DESCRIPTION", True, COLOR_GRAY_TEXT)
        h_qty = self.font_subtitle.render("QTY", True, COLOR_GRAY_TEXT)
        h_price = self.font_subtitle.render("PRICE", True, COLOR_GRAY_TEXT)
        
        self.screen.blit(h_item, (785, 172))
        self.screen.blit(h_qty, (1060, 172))
        self.screen.blit(h_price, (1160, 172))
        pygame.draw.line(self.screen, COLOR_BORDER, (785, 195), (1235, 195), 1)

        if not self.cart_items or self.current_state in [STATE_IDLE, STATE_GREET]:
            empty_text = self.font_body.render("No items scanned yet.", True, COLOR_GRAY_TEXT)
            self.screen.blit(empty_text, (760 + (500 - empty_text.get_width()) // 2, 280))
            
            hint_text = self.font_subtitle.render("Items will appear here automatically upon tray detection.", True, COLOR_BORDER)
            self.screen.blit(hint_text, (760 + (500 - hint_text.get_width()) // 2, 310))
        else:
            start_y = 210
            for idx, item in enumerate(self.cart_items):
                row_y = start_y + (idx * 40)
                if idx % 2 == 0:
                    pygame.draw.rect(self.screen, COLOR_BG_GRAY, (785, row_y - 4, 450, 34), border_radius=4)
                
                item_name = self.font_body_bold.render(item["name"], True, COLOR_CHARCOAL)
                item_qty = self.font_body.render(f"x{item['qty']}", True, COLOR_CHARCOAL)
                item_price = self.font_body_bold.render(f"₱{item['price'] * item['qty']:.2f}", True, COLOR_NAVY)

                self.screen.blit(item_name, (795, row_y + 2))
                self.screen.blit(item_qty, (1065, row_y + 2))
                self.screen.blit(item_price, (1160, row_y + 2))

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
            btn_bg = COLOR_BORDER
            btn_text = "Awaiting Student ID..."
            text_color = COLOR_WHITE
        elif self.current_state == STATE_GREET:
            btn_bg = COLOR_GOLD
            btn_text = "Initializing AI Tray Scanner..."
            text_color = COLOR_NAVY
        elif self.current_state == STATE_SCANNING:
            btn_bg = COLOR_GOLD_HOVER if is_hovered else COLOR_GOLD
            btn_text = f"Tap ID Card Again to Confirm & Pay ₱{self.total_amount:.2f}"
            text_color = COLOR_NAVY
        elif self.current_state == STATE_SETTLEMENT:
            student_bal = self.active_student["balance"] if self.active_student else 0.0
            if student_bal + self.total_amount >= self.total_amount and self.status_message.startswith("Payment Successful"):
                btn_bg = COLOR_SUCCESS
                btn_text = "✓ Payment Approved — Resetting..."
                text_color = COLOR_WHITE
            else:
                btn_bg = COLOR_DANGER
                btn_text = "✕ Insufficient Funds — Press R to Reset"
                text_color = COLOR_WHITE

        pygame.draw.rect(self.screen, btn_bg, btn_rect, border_radius=8)
        if is_hovered and self.current_state in [STATE_SCANNING, STATE_SETTLEMENT]:
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

        keybind_surf = self.font_subtitle.render("[SPACE: Tap ID | 1/2/3/4: Spoken Voice Tests | R: Reset]", True, COLOR_GOLD)
        self.screen.blit(keybind_surf, (SCREEN_WIDTH - keybind_surf.get_width() - 25, 692))

    def run(self):
        running = True
        print("=============================================================")
        print("   NOVALUNCH STUDENT KIOSK GUI TERMINAL INITIALIZED         ")
        print("=============================================================")
        print("  Controls & Shortcuts:")
        print("  - [SPACEBAR] : Simulate Student RFID Card Tap")
        print("  - [1]        : Speak 'Successfully scanned!'")
        print("  - [2]        : Speak 'Scanned Pork Adobo and Steamed Rice'")
        print("  - [3]        : Speak 'Total is 115 pesos'")
        print("  - [4]        : Speak Full Scan Announcement")
        print("  - [I]        : Toggle Insufficient Balance Mode")
        print("  - [C]        : Toggle Camera On/Off")
        print("  - [R]        : Reset to STATE_IDLE")
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
                    elif event.key == pygame.K_i:
                        self.insufficient_balance_mode = not self.insufficient_balance_mode
                        mode_str = "ENABLED (₱50.00)" if self.insufficient_balance_mode else "DISABLED (₱150.00)"
                        print(f"[DEMO OPTION] Insufficient balance simulation: {mode_str}")
                    elif event.key == pygame.K_c:
                        is_on = self.camera_thread.toggle_manual()
                        cam_str = "ENABLED" if is_on else "DISABLED (Fallback Active)"
                        print(f"[DEMO OPTION] Manual Camera Hardware State: {cam_str}")

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
                if self.status_message.startswith("Payment Successful") and (now - self.state_timer >= 3.0):
                    self.transition_to_state(STATE_IDLE)

            self.screen.fill(COLOR_BG_GRAY)

            self.render_header()
            self.render_left_panel()
            self.render_right_panel()
            self.render_footer()

            pygame.display.flip()
            self.clock.tick(TARGET_FPS)

        self.camera_thread.stop()
        pygame.quit()
        sys.exit(0)

if __name__ == "__main__":
    app = NovaLunchKioskGUI()
    app.run()
