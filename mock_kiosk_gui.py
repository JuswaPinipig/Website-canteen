#!/usr/bin/env python3
"""
NovaLunch Automated Canteen Kiosk - Mock Student-Facing GUI Terminal
======================================================================
A crash-proof, zero-hardware Pygame interface for NovaLunch.

Features:
- Pure Pygame implementation (NO OpenCV / cv2 dependencies).
- Real-Time Voice/TTS Announcements ("Successfully scanned", "Scanned Adobo & Rice", "Total is ₱115.00").
- 5-State Motion-Aware Controller: IDLE -> GREET -> SCANNING -> STABILITY_COUNTDOWN -> SETTLEMENT.
- Quiet Luxury Institutional Design System (Saint Joseph College Branding).
"""

import sys
import time
import math
import shutil
import subprocess
import threading
import numpy as np
import pygame

# ==============================================================================
# CONFIGURATION & COLOR PALETTE (SAINT JOSEPH COLLEGE BRAND SYSTEM)
# ==============================================================================
SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
TARGET_FPS = 60

# Quiet Luxury Institutional Palette
COLOR_BURGUNDY_DARK = (45, 8, 14)       # Deep Maroon/Burgundy Backdrop (#2D080E)
COLOR_BURGUNDY = (74, 14, 23)           # Primary School Burgundy (#4A0E17)
COLOR_BURGUNDY_LIGHT = (105, 25, 36)    # Lighter Accent Burgundy
COLOR_GOLD = (245, 158, 11)             # Warm Amber Gold Accent (#F59E0B)
COLOR_GOLD_DARK = (217, 119, 6)         # Deep Gold (#D97706)
COLOR_GOLD_LIGHT = (254, 243, 199)      # Soft Gold Tint (#FEF3C7)

COLOR_BG_SURFACE = (248, 250, 252)      # Ultra-clean Canvas Background (#F8FAFC)
COLOR_CARD_BG = (255, 255, 255)         # Card Fill (#FFFFFF)
COLOR_CARD_ALT = (241, 245, 249)        # Alternating Table Row (#F1F5F9)
COLOR_CARD_BORDER = (226, 232, 240)     # Delicate Card Stroke (#E2E8F0)

COLOR_TEXT_MAIN = (15, 23, 42)          # Slate Onyx Text (#0F172A)
COLOR_TEXT_MUTED = (100, 116, 139)      # Slate Gray Muted Text (#64748B)
COLOR_WHITE = (255, 255, 255)           # Pure White (#FFFFFF)

COLOR_EMERALD = (16, 185, 129)          # E-Wallet Success Green (#10B981)
COLOR_EMERALD_BG = (236, 253, 245)      # Light Emerald Pill Fill
COLOR_AMBER = (245, 158, 11)            # Warning Amber (#F59E0B)
COLOR_AMBER_BG = (254, 243, 199)        # Warning Amber Pill Fill
COLOR_ROSE = (225, 29, 72)              # Alert Danger Red (#E11D48)
COLOR_CYAN = (6, 182, 212)              # Active HUD Cyan (#06B6D4)

# State Constants
STATE_IDLE = 1
STATE_GREET = 2
STATE_SCANNING = 3
STATE_STABILITY_COUNTDOWN = 5
STATE_SETTLEMENT = 4
STATE_ERROR = 6  # RFID not enrolled or scan failure

# Mock Student Registry (keyed by RFID UID)
# Students without rfid_uid cannot be identified at the kiosk
MOCK_STUDENT_REGISTRY = {
    "RFID-883921": {
        "name": "Adi Nonog",
        "student_id": "2023-01900",
        "rfid_uid": "RFID-883921",
        "balance": 150.00
    },
    "9A-4F-21-C8": {
        "name": "Maria Clara",
        "student_id": "2023-02011",
        "rfid_uid": "9A-4F-21-C8",
        "balance": 320.00
    }
}

# Student with NO RFID (to demonstrate the error state in simulation)
MOCK_UNLINKED_STUDENT = {
    "name": "Jose Rizal",
    "student_id": "2026-03100",
    "rfid_uid": None,  # No RFID badge enrolled
    "balance": 0.00
}

# Default active demo student
MOCK_STUDENT = MOCK_STUDENT_REGISTRY["RFID-883921"]

# Mock Scanned Food Items (Adobo & Rice)
MOCK_ITEMS = [
    {"name": "Pork Adobo", "category": "MEAL", "qty": 1, "price": 100.00},
    {"name": "Steamed Rice", "category": "RICE", "qty": 1, "price": 15.00}
]

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
    sounds = {"success": None, "tick": None, "error": None}
    try:
        pygame.mixer.init(frequency=44100, size=-16, channels=2, buffer=512)
        sample_rate = 44100
        
        # 1. Success Chime Sound
        dur_s = 0.35
        t_s = np.linspace(0, dur_s, int(sample_rate * dur_s), False)
        w1 = np.sin(2 * np.pi * 523.25 * t_s) * 0.3
        w2 = np.sin(2 * np.pi * 659.25 * t_s) * 0.3
        w3 = np.sin(2 * np.pi * 783.99 * t_s) * 0.3
        env_s = np.exp(-4.0 * t_s)
        arr_s = ((w1 + w2 + w3) * env_s * 32767).astype(np.int16)
        sounds["success"] = pygame.sndarray.make_sound(np.column_stack((arr_s, arr_s)))

        # 2. Countdown Tick Sound (880Hz)
        dur_t = 0.08
        t_t = np.linspace(0, dur_t, int(sample_rate * dur_t), False)
        wt = np.sin(2 * np.pi * 880.0 * t_t) * 0.25
        env_t = np.exp(-15.0 * t_t)
        arr_t = (wt * env_t * 32767).astype(np.int16)
        sounds["tick"] = pygame.sndarray.make_sound(np.column_stack((arr_t, arr_t)))

    except Exception as e:
        print(f"[AUDIO WARN] Audio synthesizer warning: {e}")
    return sounds

# ==============================================================================
# MOCK KIOSK APPLICATION CLASS
# ==============================================================================
class NovaLunchMockKioskGUI:
    def __init__(self):
        pygame.init()
        pygame.font.init()
        pygame.display.set_caption("Saint Joseph College NovaLunch Terminal #01 — Mock Kiosk GUI")

        self.screen = pygame.display.set_mode((SCREEN_WIDTH, SCREEN_HEIGHT))
        self.clock = pygame.time.Clock()

        # Typography System
        self.font_brand_sub = pygame.font.SysFont("Trebuchet MS", 11, bold=True)
        self.font_title = pygame.font.SysFont("Trebuchet MS", 22, bold=True)
        self.font_subtitle = pygame.font.SysFont("Trebuchet MS", 13)
        self.font_subtitle_bold = pygame.font.SysFont("Trebuchet MS", 13, bold=True)
        self.font_header = pygame.font.SysFont("Trebuchet MS", 18, bold=True)
        self.font_body = pygame.font.SysFont("Trebuchet MS", 15)
        self.font_body_bold = pygame.font.SysFont("Trebuchet MS", 15, bold=True)
        self.font_large = pygame.font.SysFont("Trebuchet MS", 30, bold=True)
        self.font_footer = pygame.font.SysFont("Trebuchet MS", 14)
        self.font_timer_large = pygame.font.SysFont("Trebuchet MS", 36, bold=True)
        self.font_timer_badge = pygame.font.SysFont("Trebuchet MS", 14, bold=True)

        # State Machine Initialization
        self.current_state = STATE_IDLE
        self.active_student = None
        self.cart_items = []
        self.total_amount = 0.0
        self.state_timer = 0.0
        self.status_message = "Welcome to NovaLunch! Please tap your Student ID Card to begin."

        # Motion & 5-Second Stability Countdown System
        self.countdown_remaining = 5.0
        self.last_tick_sec = 5
        self.motion_detected = False
        self.motion_voice_alerted = False

        # Audio Sound Effects
        self.sounds = create_synthesized_sounds()

        # Interactive UI Rectangles
        self.action_button_rect = pygame.Rect(750, 565, 490, 55)
        
        # Flow Step Toolbar Buttons
        self.btn_step1 = pygame.Rect(30, 575, 160, 45)
        self.btn_step2 = pygame.Rect(200, 575, 165, 45)
        self.btn_step3 = pygame.Rect(375, 575, 165, 45)
        self.btn_step4 = pygame.Rect(550, 575, 172, 45)

    def execute_simulation_step(self, step):
        """Executes a specific step in the 4-stage checkout flow."""
        if step == 1:
            print("[SIMULATION FLOW] Key [1] Pressed: Step 1 — Tap Student RFID Card")
            self.transition_to_state(STATE_GREET)
        elif step == 2:
            print("[SIMULATION FLOW] Key [2] Pressed: Step 2 — AI Vision Tray Object Scan")
            self.transition_to_state(STATE_SCANNING)
        elif step == 3:
            print("[SIMULATION FLOW] Key [3] Pressed: Step 3 — Calibrate 5-Second Stability Countdown")
            self.transition_to_state(STATE_STABILITY_COUNTDOWN)
        elif step == 4:
            print("[SIMULATION FLOW] Key [4] Pressed: Step 4 — Execute Auto-Deduction & Settlement")
            self.transition_to_state(STATE_SETTLEMENT)

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
            self.countdown_remaining = 5.0
            self.motion_detected = False
            self.motion_voice_alerted = False
            self.status_message = "Welcome to NovaLunch! Please tap your Student ID Card to begin."

        elif new_state == STATE_ERROR:
            # RFID card scanned but not enrolled / not found in system
            self.status_message = "ERROR: RFID card not enrolled. Visit canteen admin to link your badge."
            speak_text("Card not recognized. Please visit the canteen admin to register your RFID badge.")

        elif new_state == STATE_GREET:
            self.cart_items = []
            self.total_amount = 0.0
            self.status_message = f"Hello {self.active_student['name']}! Please place items on the tray."
            speak_text(f"Welcome {self.active_student['name']}! Please place items on the tray.")

        elif new_state == STATE_SCANNING:
            self.cart_items = list(MOCK_ITEMS)
            self.total_amount = sum(item["price"] * item["qty"] for item in self.cart_items)
            self.status_message = "Items detected! Calibrating motion stability..."
            speak_text("Successfully scanned Pork Adobo and Steamed Rice. Total is 115 pesos.")

        elif new_state == STATE_STABILITY_COUNTDOWN:
            self.countdown_remaining = 5.0
            self.last_tick_sec = 5
            self.motion_voice_alerted = False
            self.status_message = f"🟢 Tray stable. Auto-deducting ₱{self.total_amount:.2f} in 5.0s..."
            speak_text("Tray stable. Auto deduction in 5 seconds.")

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
                speak_text(f"Payment successful! Remaining balance: {int(rem_balance)} pesos. Thank you!")
            else:
                self.status_message = "Insufficient Funds! Cashier POS override required."
                speak_text("Warning! Insufficient balance. Cashier POS override required.")

    def handle_rfid_tap(self, simulated_uid=None):
        """Process an RFID card scan. Looks up student by UID, errors if not enrolled."""
        if self.current_state == STATE_IDLE:
            # Look up student by UID
            uid = simulated_uid or "RFID-883921"  # default demo UID
            matched = MOCK_STUDENT_REGISTRY.get(uid.upper())
            if matched:
                print(f"[RFID SCAN] UID '{uid}' matched student: {matched['name']} ({matched['student_id']})")
                self.active_student = dict(matched)
                self.execute_simulation_step(1)
            else:
                print(f"[RFID SCAN ERROR] UID '{uid}' not found in registry — not enrolled")
                self.transition_to_state(STATE_ERROR)

        elif self.current_state == STATE_ERROR:
            # Any tap clears the error and returns to IDLE
            self.transition_to_state(STATE_IDLE)

        elif self.current_state == STATE_GREET:
            self.execute_simulation_step(2)
        elif self.current_state == STATE_SCANNING:
            self.execute_simulation_step(3)
        elif self.current_state == STATE_STABILITY_COUNTDOWN:
            self.execute_simulation_step(4)
        elif self.current_state == STATE_SETTLEMENT:
            self.transition_to_state(STATE_IDLE)

    def simulate_unlinked_rfid_tap(self):
        """Simulate a card tap for a student with NO RFID enrolled (error demo)."""
        print("[SIMULATION] Key [E] Pressed: Simulating unlinked RFID student tap")
        unlinked_uid = "UNLINKED-9999"
        print(f"[RFID SCAN ERROR] UID '{unlinked_uid}' — Student '{MOCK_UNLINKED_STUDENT['name']}' has NO RFID badge enrolled")
        self.transition_to_state(STATE_ERROR)

    # --------------------------------------------------------------------------
    # MODERN INSTITUTIONAL RENDERERS
    # --------------------------------------------------------------------------
    def render_header(self):
        # Header Container
        pygame.draw.rect(self.screen, COLOR_BURGUNDY_DARK, (0, 0, SCREEN_WIDTH, 82))
        pygame.draw.rect(self.screen, COLOR_GOLD_DARK, (0, 80, SCREEN_WIDTH, 2))

        # School Emblem Badge Graphics
        pygame.draw.circle(self.screen, COLOR_GOLD, (42, 41), 22)
        pygame.draw.circle(self.screen, COLOR_BURGUNDY, (42, 41), 19)
        
        # Crest letters 'SJC'
        emblem_txt = self.font_subtitle_bold.render("SJC", True, COLOR_GOLD)
        self.screen.blit(emblem_txt, (42 - emblem_txt.get_width() // 2, 41 - emblem_txt.get_height() // 2))

        # Title & Subtitle Branding
        school_tag = self.font_brand_sub.render("SAINT JOSEPH COLLEGE OF NOVALICHES, INC.", True, COLOR_GOLD)
        kiosk_title = self.font_title.render("NovaLunch Kiosk Terminal #01 (Mock GUI)", True, COLOR_WHITE)
        
        self.screen.blit(school_tag, (76, 16))
        self.screen.blit(kiosk_title, (76, 34))

        # Active Student / E-Wallet Profile Pill (Right Side)
        if self.active_student and self.current_state != STATE_IDLE:
            student_name = self.active_student["name"]
            student_id = self.active_student.get("id", "RFID-883921")
            balance_val = self.active_student["balance"]

            # Profile Badge Container
            card_rect = pygame.Rect(SCREEN_WIDTH - 380, 12, 355, 58)
            pygame.draw.rect(self.screen, COLOR_BURGUNDY, card_rect, border_radius=12)
            pygame.draw.rect(self.screen, COLOR_GOLD_DARK, card_rect, width=1, border_radius=12)

            # Avatar Circle
            pygame.draw.circle(self.screen, COLOR_GOLD, (card_rect.left + 30, card_rect.top + 29), 18)
            avatar_txt = self.font_subtitle_bold.render("AN", True, COLOR_BURGUNDY_DARK)
            self.screen.blit(avatar_txt, (card_rect.left + 30 - avatar_txt.get_width() // 2, card_rect.top + 29 - avatar_txt.get_height() // 2))

            # Name & ID
            name_surf = self.font_body_bold.render(student_name, True, COLOR_WHITE)
            id_surf = self.font_brand_sub.render(f"RFID: {student_id}", True, COLOR_GOLD_LIGHT)
            self.screen.blit(name_surf, (card_rect.left + 58, card_rect.top + 10))
            self.screen.blit(id_surf, (card_rect.left + 58, card_rect.top + 33))

            # Balance Pill
            is_enough = balance_val >= self.total_amount
            bal_fill = COLOR_EMERALD_BG if is_enough else COLOR_AMBER_BG
            bal_border = COLOR_EMERALD if is_enough else COLOR_ROSE
            bal_text_color = COLOR_EMERALD if is_enough else COLOR_ROSE

            bal_str = f"₱{balance_val:.2f}"
            bal_surf = self.font_body_bold.render(bal_str, True, bal_text_color)
            bal_rect = pygame.Rect(card_rect.right - bal_surf.get_width() - 24, card_rect.top + 14, bal_surf.get_width() + 16, 30)
            
            pygame.draw.rect(self.screen, bal_fill, bal_rect, border_radius=15)
            pygame.draw.rect(self.screen, bal_border, bal_rect, width=1, border_radius=15)
            self.screen.blit(bal_surf, (bal_rect.x + 8, bal_rect.y + 5))

        else:
            # Idle Status Pill
            idle_rect = pygame.Rect(SCREEN_WIDTH - 300, 20, 275, 42)
            pygame.draw.rect(self.screen, (30, 8, 12), idle_rect, border_radius=21)
            pygame.draw.rect(self.screen, COLOR_GOLD_DARK, idle_rect, width=1, border_radius=21)

            pygame.draw.circle(self.screen, COLOR_GOLD, (idle_rect.left + 22, idle_rect.centery), 6)
            idle_lbl = self.font_subtitle_bold.render("Awaiting Student RFID Tap...", True, COLOR_GOLD_LIGHT)
            self.screen.blit(idle_lbl, (idle_rect.left + 36, idle_rect.centery - idle_lbl.get_height() // 2))

    def render_left_panel(self):
        panel_rect = pygame.Rect(20, 98, 715, 545)
        
        # White Card Container
        pygame.draw.rect(self.screen, COLOR_CARD_BG, panel_rect, border_radius=14)
        pygame.draw.rect(self.screen, COLOR_CARD_BORDER, panel_rect, width=1, border_radius=14)

        # Header Title
        header_surf = self.font_header.render("SIMULATED OVERHEAD TRAY SCANNER", True, COLOR_BURGUNDY)
        self.screen.blit(header_surf, (36, 114))

        # Status Indicator Badge
        status_text = "SIMULATION ENGINE"
        badge_bg = COLOR_GOLD_LIGHT
        badge_fg = COLOR_GOLD_DARK

        badge_lbl = self.font_brand_sub.render(status_text, True, badge_fg)
        badge_w = badge_lbl.get_width() + 24
        badge_rect = pygame.Rect(panel_rect.right - badge_w - 20, 112, badge_w, 24)
        
        pygame.draw.rect(self.screen, badge_bg, badge_rect, border_radius=12)
        pygame.draw.circle(self.screen, badge_fg, (badge_rect.left + 12, badge_rect.centery), 4)
        self.screen.blit(badge_lbl, (badge_rect.left + 20, badge_rect.centery - badge_lbl.get_height() // 2))

        # Video Frame Area
        video_area = pygame.Rect(32, 148, 691, 405)
        pygame.draw.rect(self.screen, COLOR_CARD_ALT, video_area, border_radius=10)

        # Grid lines
        for x in range(video_area.left, video_area.right, 40):
            pygame.draw.line(self.screen, (226, 232, 240), (x, video_area.top), (x, video_area.bottom), 1)
        for y in range(video_area.top, video_area.bottom, 40):
            pygame.draw.line(self.screen, (226, 232, 240), (video_area.left, y), (video_area.right, y), 1)

        # Render Bounding Box Graphics when scanning
        if self.current_state in [STATE_SCANNING, STATE_STABILITY_COUNTDOWN, STATE_SETTLEMENT]:
            # Mock Pork Adobo Box
            b1 = pygame.Rect(32 + 80, 148 + 80, 240, 200)
            pygame.draw.rect(self.screen, COLOR_GOLD, b1, width=2, border_radius=8)
            l1 = self.font_subtitle_bold.render(" Pork Adobo (96%) • ₱100.00 ", True, COLOR_WHITE)
            bg1 = pygame.Rect(b1.x, b1.y - 24, l1.get_width() + 8, 24)
            pygame.draw.rect(self.screen, COLOR_BURGUNDY_DARK, bg1, border_top_left_radius=6, border_top_right_radius=6)
            self.screen.blit(l1, (b1.x + 4, b1.y - 20))

            # Mock Steamed Rice Box
            b2 = pygame.Rect(32 + 360, 148 + 140, 220, 180)
            pygame.draw.rect(self.screen, COLOR_GOLD, b2, width=2, border_radius=8)
            l2 = self.font_subtitle_bold.render(" Steamed Rice (92%) • ₱15.00 ", True, COLOR_WHITE)
            bg2 = pygame.Rect(b2.x, b2.y - 24, l2.get_width() + 8, 24)
            pygame.draw.rect(self.screen, COLOR_BURGUNDY_DARK, bg2, border_top_left_radius=6, border_top_right_radius=6)
            self.screen.blit(l2, (b2.x + 4, b2.y - 20))

        else:
            cx, cy = video_area.centerx, video_area.centery - 20
            pygame.draw.circle(self.screen, COLOR_WHITE, (cx, cy), 42)
            pygame.draw.circle(self.screen, COLOR_BURGUNDY, (cx, cy), 42, width=2)
            pygame.draw.circle(self.screen, COLOR_BURGUNDY, (cx, cy), 18, width=3)
            pygame.draw.circle(self.screen, COLOR_GOLD, (cx + 7, cy - 7), 4)

            main_text = self.font_header.render("Mock Camera Viewport", True, COLOR_BURGUNDY)
            sub_text = self.font_subtitle.render("Press SPACEBAR to simulate Student RFID Card Tap & AI Tray Scan", True, COLOR_TEXT_MUTED)
            self.screen.blit(main_text, (cx - main_text.get_width() // 2, cy + 60))
            self.screen.blit(sub_text, (cx - sub_text.get_width() // 2, cy + 88))

        # Render 5-Second Motion Stability Timer & Visual HUD Overlay
        if self.current_state in [STATE_SCANNING, STATE_STABILITY_COUNTDOWN, STATE_SETTLEMENT]:
            self.render_timer_hud(video_area)

        pygame.draw.rect(self.screen, COLOR_CARD_BORDER, video_area, width=1, border_radius=10)
        self.render_voice_test_toolbar()

    def render_timer_hud(self, video_area):
        if self.current_state == STATE_STABILITY_COUNTDOWN:
            if self.motion_detected:
                banner_bg = COLOR_AMBER
                banner_border = COLOR_WHITE
                banner_text = "⚠️ TRAY MOTION DETECTED — TIMER PAUSED"
            else:
                banner_bg = COLOR_BURGUNDY_DARK
                banner_border = COLOR_CYAN
                banner_text = f"🟢 TRAY STABLE — AUTO DEDUCTION IN {self.countdown_remaining:.1f}s"

            text_surf = self.font_timer_badge.render(banner_text, True, COLOR_WHITE)
            banner_rect = pygame.Rect(video_area.centerx - text_surf.get_width() // 2 - 16, video_area.top + 12, text_surf.get_width() + 32, 34)
            
            pygame.draw.rect(self.screen, banner_bg, banner_rect, border_radius=17)
            pygame.draw.rect(self.screen, banner_border, banner_rect, width=1, border_radius=17)
            self.screen.blit(text_surf, (banner_rect.x + 16, banner_rect.y + 7))

            # Radial Circular Gauge Overlay
            gauge_cx = video_area.right - 60
            gauge_cy = video_area.top + 60
            radius = 42

            pygame.draw.circle(self.screen, (15, 23, 42), (gauge_cx, gauge_cy), radius)
            pygame.draw.circle(self.screen, COLOR_WHITE, (gauge_cx, gauge_cy), radius, width=2)

            progress_ratio = max(0.0, min(1.0, 1.0 - (self.countdown_remaining / 5.0)))
            arc_color = COLOR_AMBER if self.motion_detected else (COLOR_CYAN if progress_ratio < 0.8 else COLOR_EMERALD)
            
            start_angle = -math.pi / 2
            end_angle = start_angle + (2 * math.pi * progress_ratio)
            
            for i in range(24):
                ang = start_angle + (2 * math.pi * (i / 24.0))
                if ang <= end_angle:
                    px = int(gauge_cx + (radius - 5) * math.cos(ang))
                    py = int(gauge_cy + (radius - 5) * math.sin(ang))
                    pygame.draw.circle(self.screen, arc_color, (px, py), 3)

            if self.motion_detected:
                num_surf = self.font_subtitle_bold.render("PAUSE", True, COLOR_AMBER)
            else:
                num_surf = self.font_timer_large.render(f"{int(math.ceil(self.countdown_remaining))}", True, arc_color)

            tx = gauge_cx - num_surf.get_width() // 2
            ty = gauge_cy - num_surf.get_height() // 2
            self.screen.blit(num_surf, (tx, ty))

        elif self.current_state == STATE_SETTLEMENT:
            banner_rect = pygame.Rect(video_area.centerx - 210, video_area.centery - 45, 420, 90)
            pygame.draw.rect(self.screen, COLOR_EMERALD, banner_rect, border_radius=14)
            pygame.draw.rect(self.screen, COLOR_WHITE, banner_rect, width=2, border_radius=14)

            t1 = self.font_large.render("✓ PAYMENT APPROVED", True, COLOR_WHITE)
            t2 = self.font_subtitle_bold.render(f"Deducted ₱{self.total_amount:.2f} — Session Resetting...", True, COLOR_WHITE)
            
            self.screen.blit(t1, (banner_rect.centerx - t1.get_width() // 2, banner_rect.y + 16))
            self.screen.blit(t2, (banner_rect.centerx - t2.get_width() // 2, banner_rect.y + 54))

    def render_flow_step_toolbar(self):
        mouse_pos = pygame.mouse.get_pos()
        btn_configs = [
            (self.btn_step1, "Step 1: Tap ID", "💳", COLOR_BURGUNDY, "[1]"),
            (self.btn_step2, "Step 2: AI Scan", "🍱", COLOR_BURGUNDY, "[2]"),
            (self.btn_step3, "Step 3: 5s Timer", "⏳", COLOR_BURGUNDY, "[3]"),
            (self.btn_step4, "Step 4: Pay ₱115", "✓", COLOR_GOLD_DARK, "[4]")
        ]

        for rect, label, icon, bg_color, key_hint in btn_configs:
            is_hovered = rect.collidepoint(mouse_pos)
            fill_color = COLOR_GOLD if (is_hovered and bg_color == COLOR_GOLD_DARK) else (COLOR_BURGUNDY_LIGHT if is_hovered else bg_color)
            
            pygame.draw.rect(self.screen, fill_color, rect, border_radius=8)
            if is_hovered:
                pygame.draw.rect(self.screen, COLOR_GOLD, rect, width=1, border_radius=8)

            btn_str = f"{icon} {label} {key_hint}"
            text_color = COLOR_BURGUNDY_DARK if bg_color == COLOR_GOLD_DARK else COLOR_WHITE
            text_surf = self.font_subtitle_bold.render(btn_str, True, text_color)
            
            tx = rect.x + (rect.width - text_surf.get_width()) // 2
            ty = rect.y + (rect.height - text_surf.get_height()) // 2
            self.screen.blit(text_surf, (tx, ty))

    def render_right_panel(self):
        panel_rect = pygame.Rect(750, 98, 510, 545)
        
        # White Card Container
        pygame.draw.rect(self.screen, COLOR_CARD_BG, panel_rect, border_radius=14)
        pygame.draw.rect(self.screen, COLOR_CARD_BORDER, panel_rect, width=1, border_radius=14)

        title_surf = self.font_header.render("RUNNING TALLY", True, COLOR_BURGUNDY)
        subtitle_surf = self.font_subtitle.render("Scanned Tray Items & Price Breakdown", True, COLOR_TEXT_MUTED)
        self.screen.blit(title_surf, (775, 114))
        self.screen.blit(subtitle_surf, (775, 138))

        pygame.draw.line(self.screen, COLOR_CARD_BORDER, (775, 162), (1235, 162), 1)
        
        h_item = self.font_brand_sub.render("ITEM DESCRIPTION", True, COLOR_TEXT_MUTED)
        h_qty = self.font_brand_sub.render("QTY", True, COLOR_TEXT_MUTED)
        h_price = self.font_brand_sub.render("PRICE", True, COLOR_TEXT_MUTED)
        
        self.screen.blit(h_item, (775, 168))
        self.screen.blit(h_qty, (1060, 168))
        self.screen.blit(h_price, (1165, 168))
        pygame.draw.line(self.screen, COLOR_CARD_BORDER, (775, 188), (1235, 188), 1)

        if not self.cart_items or self.current_state in [STATE_IDLE, STATE_GREET]:
            empty_text = self.font_body.render("No items scanned yet.", True, COLOR_TEXT_MUTED)
            self.screen.blit(empty_text, (750 + (510 - empty_text.get_width()) // 2, 280))
            
            hint_text = self.font_subtitle.render("Scanned food items will appear here automatically.", True, COLOR_CARD_BORDER)
            self.screen.blit(hint_text, (750 + (510 - hint_text.get_width()) // 2, 308))
        else:
            start_y = 202
            for idx, item in enumerate(self.cart_items):
                row_y = start_y + (idx * 44)
                
                if idx % 2 == 0:
                    pygame.draw.rect(self.screen, COLOR_CARD_ALT, (775, row_y - 2, 460, 38), border_radius=6)
                
                cat_tag = self.font_brand_sub.render(f"[{item.get('category', 'ITEM')}]", True, COLOR_GOLD_DARK)
                self.screen.blit(cat_tag, (785, row_y + 9))

                item_name = self.font_body_bold.render(item["name"], True, COLOR_TEXT_MAIN)
                item_qty = self.font_body.render(f"x{item['qty']}", True, COLOR_TEXT_MAIN)
                item_price = self.font_body_bold.render(f"₱{item['price'] * item['qty']:.2f}", True, COLOR_BURGUNDY)

                self.screen.blit(item_name, (840, row_y + 8))
                self.screen.blit(item_qty, (1065, row_y + 8))
                self.screen.blit(item_price, (1165, row_y + 8))

        pygame.draw.line(self.screen, COLOR_CARD_BORDER, (775, 470), (1235, 470), 1)

        total_lbl = self.font_header.render("TOTAL AMOUNT:", True, COLOR_TEXT_MAIN)
        total_val = self.font_large.render(f"₱{self.total_amount:.2f}", True, COLOR_BURGUNDY)
        
        self.screen.blit(total_lbl, (775, 492))
        self.screen.blit(total_val, (1235 - total_val.get_width(), 484))

        self.render_action_button()

    def render_action_button(self):
        btn_rect = self.action_button_rect
        mouse_pos = pygame.mouse.get_pos()
        is_hovered = btn_rect.collidepoint(mouse_pos)

        if self.current_state == STATE_IDLE:
            btn_bg = COLOR_CARD_BORDER
            btn_text = "Awaiting Student ID Card Tap..."
            text_color = COLOR_TEXT_MUTED
        elif self.current_state == STATE_ERROR:
            btn_bg = COLOR_ROSE
            btn_text = "⛔ RFID Not Enrolled — Tap Anywhere to Dismiss"
            text_color = COLOR_WHITE
        elif self.current_state == STATE_GREET:
            btn_bg = COLOR_GOLD
            btn_text = "Initializing AI Tray Scanner..."
            text_color = COLOR_BURGUNDY_DARK
        elif self.current_state == STATE_SCANNING:
            btn_bg = COLOR_GOLD
            btn_text = "Scanning Items & Calibrating Motion..."
            text_color = COLOR_BURGUNDY_DARK
        elif self.current_state == STATE_STABILITY_COUNTDOWN:
            if self.motion_detected:
                btn_bg = COLOR_AMBER
                btn_text = "⚠️ Tray Motion Detected — Countdown Paused"
                text_color = COLOR_WHITE
            else:
                btn_bg = COLOR_GOLD_DARK if is_hovered else COLOR_GOLD
                btn_text = f"⏳ Auto-Deducting in {self.countdown_remaining:.1f}s (Tap to Pay Now)"
                text_color = COLOR_BURGUNDY_DARK
        elif self.current_state == STATE_SETTLEMENT:
            btn_bg = COLOR_EMERALD
            btn_text = "✓ Payment Approved — Resetting..."
            text_color = COLOR_WHITE

        pygame.draw.rect(self.screen, btn_bg, btn_rect, border_radius=10)
        if is_hovered and self.current_state in [STATE_SCANNING, STATE_STABILITY_COUNTDOWN, STATE_SETTLEMENT]:
            pygame.draw.rect(self.screen, COLOR_BURGUNDY_DARK, btn_rect, width=2, border_radius=10)

        text_surf = self.font_body_bold.render(btn_text, True, text_color)
        tx = btn_rect.x + (btn_rect.width - text_surf.get_width()) // 2
        ty = btn_rect.y + (btn_rect.height - text_surf.get_height()) // 2
        self.screen.blit(text_surf, (tx, ty))

    def render_footer(self):
        footer_rect = pygame.Rect(0, 678, SCREEN_WIDTH, 42)
        pygame.draw.rect(self.screen, COLOR_BURGUNDY_DARK, footer_rect)
        pygame.draw.rect(self.screen, COLOR_GOLD_DARK, (0, 678, SCREEN_WIDTH, 2))

        msg_surf = self.font_footer.render(f"STATUS: {self.status_message}", True, COLOR_WHITE)
        self.screen.blit(msg_surf, (24, 690))

        hints_surf = self.font_subtitle_bold.render("[SPACE: Step Flow | 1-4: Step Simulation | E: No-RFID Error Demo | M: Motion | R: Reset]", True, COLOR_GOLD)
        self.screen.blit(hints_surf, (SCREEN_WIDTH - hints_surf.get_width() - 24, 690))

    # --------------------------------------------------------------------------
    # MAIN APPLICATION LOOP
    # --------------------------------------------------------------------------
    def run(self):
        running = True
        print("=============================================================")
        print("   NOVALUNCH MOCK KIOSK GUI TERMINAL INITIALIZED             ")
        print("=============================================================")
        print("  Interactive 4-Step Simulation Controls:")
        print("  - [1] Step 1: Tap Student RFID Card (IDLE -> GREET)")
        print("  - [2] Step 2: AI Vision Tray Scan (GREET -> SCANNING)")
        print("  - [3] Step 3: Start 5s Stability Timer (SCANNING -> COUNTDOWN)")
        print("  - [4] Step 4: Auto-Deduct E-Wallet Payment (COUNTDOWN -> SETTLEMENT)")
        print("  -----------------------------------------------------------")
        print("  - [SPACEBAR] : Advance Step Flow / Tap ID / Immediate Pay")
        print("  - [E]        : Simulate Unlinked RFID Tap (ERROR state demo)")
        print("  - [M]        : Toggle Motion Simulation (Pauses 5s Timer)")
        print("  - [R]        : Reset System to STATE_IDLE")
        print("=============================================================")

        while running:
            dt = self.clock.tick(TARGET_FPS) / 1000.0

            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False

                elif event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_ESCAPE:
                        running = False
                    elif event.key == pygame.K_SPACE:
                        self.handle_rfid_tap()
                    elif event.key == pygame.K_m:
                        self.motion_detected = not self.motion_detected
                        m_str = "DETECTED (Timer Paused)" if self.motion_detected else "CLEAR (Tray Stable)"
                        print(f"[SIMULATION CUE] Hand / Tray Motion: {m_str}")
                    elif event.key == pygame.K_e:
                        self.simulate_unlinked_rfid_tap()
                    elif event.key == pygame.K_r:
                        self.transition_to_state(STATE_IDLE)
                    elif event.key in [pygame.K_1, pygame.K_KP1]:
                        self.execute_simulation_step(1)
                    elif event.key in [pygame.K_2, pygame.K_KP2]:
                        self.execute_simulation_step(2)
                    elif event.key in [pygame.K_3, pygame.K_KP3]:
                        self.execute_simulation_step(3)
                    elif event.key in [pygame.K_4, pygame.K_KP4]:
                        self.execute_simulation_step(4)

                elif event.type == pygame.MOUSEBUTTONDOWN:
                    if event.button == 1:
                        pos = event.pos
                        if self.action_button_rect.collidepoint(pos):
                            self.handle_rfid_tap()
                        elif self.btn_step1.collidepoint(pos):
                            self.execute_simulation_step(1)
                        elif self.btn_step2.collidepoint(pos):
                            self.execute_simulation_step(2)
                        elif self.btn_step3.collidepoint(pos):
                            self.execute_simulation_step(3)
                        elif self.btn_step4.collidepoint(pos):
                            self.execute_simulation_step(4)

            now = time.time()
            if self.current_state == STATE_GREET:
                if now - self.state_timer >= 1.5:
                    self.transition_to_state(STATE_SCANNING)

            elif self.current_state == STATE_SCANNING:
                if now - self.state_timer >= 1.2:
                    self.transition_to_state(STATE_STABILITY_COUNTDOWN)

            elif self.current_state == STATE_STABILITY_COUNTDOWN:
                if self.motion_detected:
                    self.countdown_remaining = 5.0
                    self.status_message = "⚠️ TRAY MOTION DETECTED — TIMER PAUSED (Keep hands clear)"
                    if not self.motion_voice_alerted:
                        speak_text("Tray motion detected. Please keep hands clear of tray.")
                        self.motion_voice_alerted = True
                else:
                    self.motion_voice_alerted = False
                    self.countdown_remaining -= dt
                    curr_sec = int(math.ceil(self.countdown_remaining))
                    
                    if curr_sec < self.last_tick_sec and curr_sec >= 1:
                        self.last_tick_sec = curr_sec
                        if self.sounds.get("tick"):
                            try:
                                self.sounds["tick"].play()
                            except Exception:
                                pass

                    self.status_message = f"🟢 TRAY STABLE — DEDUCTING ₱{self.total_amount:.2f} IN {self.countdown_remaining:.1f}s"
                    
                    if self.countdown_remaining <= 0.0:
                        self.transition_to_state(STATE_SETTLEMENT)

            elif self.current_state == STATE_SETTLEMENT:
                if now - self.state_timer >= 3.5:
                    self.transition_to_state(STATE_IDLE)

            self.screen.fill(COLOR_BG_SURFACE)

            self.render_header()
            self.render_left_panel()
            self.render_right_panel()
            self.render_footer()

            pygame.display.flip()

        pygame.quit()
        sys.exit(0)

if __name__ == "__main__":
    app = NovaLunchMockKioskGUI()
    app.run()
