import sys
import os
import csv
import subprocess
import time
import random
import datetime
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext

if getattr(sys, 'frozen', False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

CONFIG_FILE = os.path.join(BASE_DIR, "tools.cfg")
ROOT_FILE = os.path.join(BASE_DIR, "root.cfg")
REPORT_DIR = os.path.join(BASE_DIR, "reports")
LOG_DIR = os.path.join(REPORT_DIR, "logs")
LOG_FILE = os.path.join(REPORT_DIR, "launch_log.csv")
REPORT_FILE = os.path.join(REPORT_DIR, "report.txt")
LOCK_DIR = os.path.join(REPORT_DIR, "log.lock")

COLORS = {
    'bg': '#F8FAFC',
    'header_bg': '#0F172A',
    'header_fg': '#FFFFFF',
    'button': '#3B82F6',
    'button_active': '#2563EB',
    'button_text': '#FFFFFF',
    'entry_bg': '#FFFFFF',
    'list_bg': '#FFFFFF',
    'list_fg': '#334155',
    'list_select': '#DBEAFE',
    'list_select_fg': '#0F172A',
    'accent': '#10B981',
    'warn': '#EF4444'
}

FONT_DEFAULT = ('Segoe UI', 10)
FONT_BOLD = ('Segoe UI', 10, 'bold')
FONT_TITLE = ('Segoe UI', 14, 'bold')

def load_root():
    if os.path.exists(ROOT_FILE):
        with open(ROOT_FILE, 'r', encoding='utf-8') as f:
            line = f.readline().strip()
            if line:
                return line.rstrip('\\')
    return None

def save_root(path):
    with open(ROOT_FILE, 'w', encoding='utf-8') as f:
        if path:
            f.write(path.rstrip('\\'))

def load_tools():
    tools = []
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and '=' in line and not line.startswith(';'):
                    name, rest = line.split('=', 1)
                    if '|' in rest:
                        ttype, path = rest.split('|', 1)
                        ttype = ttype.strip()
                        path = path.strip().strip('"')
                    else:
                        ttype, path = 'gui', rest
                    tools.append({'name': name.strip(), 'type': ttype.strip(), 'path': path.strip()})
    return tools

def save_tools(tools):
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        for t in tools:
            f.write(f"{t['name']}={t['type']}|{t['path']}\n")

def resolve_path(relative_path, root):
    if not relative_path:
        return ""
    if os.path.isabs(relative_path) or relative_path.startswith('\\\\'):
        return relative_path
    if root:
        return os.path.join(root, relative_path)
    return relative_path

def acquire_log_lock():
    for _ in range(50):
        try:
            os.mkdir(LOCK_DIR)
            return True
        except OSError:
            time.sleep(0.1)
    return False

def release_log_lock():
    try:
        os.rmdir(LOCK_DIR)
    except OSError:
        pass

def write_log(date_str, time_str, tool, exit_code, log_path):
    if not acquire_log_lock():
        return
    try:
        file_exists = os.path.isfile(LOG_FILE)
        with open(LOG_FILE, 'a', newline='', encoding='utf-8') as f:
            writer = csv.writer(f, delimiter=';')
            if not file_exists:
                writer.writerow(['Date', 'Time', 'Tool', 'ExitCode', 'OutputLog'])
            writer.writerow([date_str, time_str, tool, exit_code, log_path])
    finally:
        release_log_lock()

def worker_process(tool_name):
    tools = load_tools()
    root = load_root()
    tool = next((t for t in tools if t['name'] == tool_name), None)
    
    if not tool:
        write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                  tool_name, 'NOT_FOUND', '')
        return
        
    exe_path = resolve_path(tool['path'], root).strip('"')
    if not os.path.exists(exe_path):
        write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                  tool_name, 'FILE_NOT_FOUND', '')
        return

    if tool['type'] == 'console':
        subprocess.Popen(
            f'start "Tool_{tool["name"]}" cmd /k "cd /d ""{os.path.dirname(exe_path)}"" && ""{exe_path}""',
            shell=True,
            creationflags=subprocess.CREATE_NEW_CONSOLE
        )
        write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                  tool_name, '0', 'Started (interactive)')
    else:
        stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + f'_{random.randint(1000,9999)}'
        log_path = os.path.join(LOG_DIR, f"{tool_name}_{stamp}.log")
        os.makedirs(LOG_DIR, exist_ok=True)
        try:
            with open(log_path, 'w', encoding='utf-8') as log_f:
                proc = subprocess.Popen([exe_path], stdout=log_f, stderr=subprocess.STDOUT,
                                        creationflags=subprocess.CREATE_NO_WINDOW)
                proc.wait()
            exit_code = str(proc.returncode)
        except Exception as e:
            exit_code = 'ERROR'
            with open(log_path, 'w', encoding='utf-8') as log_f:
                log_f.write(str(e))
                
        if os.path.exists(log_path) and os.path.getsize(log_path) == 0:
            os.remove(log_path)
            log_path = ''
            
        write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                  tool_name, exit_code, log_path)

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Лаунчер сборки")
        self.geometry("1050x700")
        self.root_path = load_root()
        self.tools = load_tools()

        self.style = ttk.Style(self)
        self.style.theme_use('clam')
        self.configure_styles()

        main_bg = tk.Frame(self, bg=COLORS['bg'])
        main_bg.pack(fill='both', expand=True)

        header = tk.Frame(main_bg, bg=COLORS['header_bg'], height=65)
        header.pack(fill='x')
        header.pack_propagate(False)
        
        title_lbl = tk.Label(header, text="🔧 ЛАУНЧЕР СБОРКИ", font=FONT_TITLE,
                             bg=COLORS['header_bg'], fg=COLORS['header_fg'])
        title_lbl.pack(side='left', padx=20, pady=15)

        self.status_var = tk.StringVar(value="Готов к работе")
        status_lbl = tk.Label(header, textvariable=self.status_var, font=FONT_BOLD,
                              bg=COLORS['header_bg'], fg=COLORS['accent'])
        status_lbl.pack(side='right', padx=20, pady=15)

        self.notebook = ttk.Notebook(main_bg)
        self.notebook.pack(fill='both', expand=True, padx=15, pady=15)

        self.tab_run = ttk.Frame(self.notebook)
        self.tab_editor = ttk.Frame(self.notebook)
        self.tab_report = ttk.Frame(self.notebook)

        self.notebook.add(self.tab_run, text="  🚀 Запуск  ")
        self.notebook.add(self.tab_editor, text="  ⚙️ Редактор  ")
        self.notebook.add(self.tab_report, text="  📊 Отчёт  ")

        self.build_run_tab()
        self.build_editor_tab()
        self.build_report_tab()

        self.refresh_tools_list()
        self.refresh_editor_list()

    def configure_styles(self):
        self.style.configure('TNotebook', background=COLORS['bg'], borderwidth=0)
        self.style.configure('TNotebook.Tab', font=FONT_BOLD, padding=[15, 8],
                             background='#E2E8F0', foreground=COLORS['list_fg'], borderwidth=0)
        self.style.map('TNotebook.Tab',
                       background=[('selected', COLORS['button'])],
                       foreground=[('selected', COLORS['button_text'])])

        self.style.configure('TFrame', background=COLORS['bg'])
        
        self.style.configure('TLabel', background=COLORS['bg'], font=FONT_DEFAULT,
                             foreground=COLORS['list_fg'])
                             
        self.style.configure('TButton', font=FONT_BOLD, padding=[10, 5],
                             background=COLORS['button'], foreground=COLORS['button_text'], borderwidth=0)
        self.style.map('TButton',
                       background=[('active', COLORS['button_active']), ('disabled', '#94A3B8')])

        self.style.configure('Treeview', font=FONT_DEFAULT, rowheight=30,
                             fieldbackground=COLORS['list_bg'],
                             background=COLORS['list_bg'],
                             foreground=COLORS['list_fg'], borderwidth=0)
        self.style.map('Treeview', 
                       background=[('selected', COLORS['list_select'])],
                       foreground=[('selected', COLORS['list_select_fg'])])
                       
        self.style.configure('Treeview.Heading', font=FONT_BOLD, padding=[5, 5],
                             background='#F1F5F9', foreground=COLORS['header_bg'], borderwidth=0)

        self.style.configure('TEntry', fieldbackground=COLORS['entry_bg'], font=FONT_DEFAULT, padding=5)
        self.style.configure('TCombobox', fieldbackground=COLORS['entry_bg'], font=FONT_DEFAULT, padding=5)
        self.style.map('TCombobox', fieldbackground=[('readonly', COLORS['entry_bg'])])

        self.style.configure('TLabelframe', background=COLORS['bg'], borderwidth=1)
        self.style.configure('TLabelframe.Label', background=COLORS['bg'], font=FONT_BOLD, foreground=COLORS['header_bg'])

    def on_tree_click(self, event):
        item = self.tree_run.identify_row(event.y)
        if item:
            if item in self.tree_run.selection():
                self.tree_run.selection_remove(item)
            else:
                self.tree_run.selection_add(item)
            return "break"

    def build_run_tab(self):
        main_frame = ttk.Frame(self.tab_run)
        main_frame.pack(fill='both', expand=True, padx=20, pady=20)

        tree_frame = ttk.LabelFrame(main_frame, text="Доступные инструменты")
        tree_frame.pack(fill='both', expand=True, pady=(0, 15))

        self.tree_run = ttk.Treeview(tree_frame, columns=('name', 'type'), show='headings', selectmode='extended')        
        self.tree_run.heading('name', text='Название инструмента', anchor='w')
        self.tree_run.heading('type', text='Тип', anchor='w')
        self.tree_run.column('name', width=400, anchor='w')
        self.tree_run.column('type', width=100, anchor='w')
        
        self.tree_run.pack(side='left', fill='both', expand=True, padx=5, pady=5)
        self.tree_run.bind('<Button-1>', self.on_tree_click)

        scroll_run = ttk.Scrollbar(tree_frame, orient='vertical', command=self.tree_run.yview)
        scroll_run.pack(side='right', fill='y', pady=5)
        self.tree_run.configure(yscrollcommand=scroll_run.set)

        btn_frame = ttk.Frame(main_frame)
        btn_frame.pack(fill='x', pady=5)
        
        ttk.Button(btn_frame, text="▶ Последовательно", command=self.run_selected_sequential).pack(side='left', padx=(0, 10))
        ttk.Button(btn_frame, text="⚡ Параллельно", command=self.run_selected_parallel).pack(side='left', padx=10)
        ttk.Button(btn_frame, text="🔄 Обновить список", command=self.refresh_tools_list).pack(side='right')

    def refresh_tools_list(self):
        self.tools = load_tools()
        self.root_path = load_root()
        for item in self.tree_run.get_children():
            self.tree_run.delete(item)
        for t in self.tools:
            self.tree_run.insert('', 'end', values=(f"  {t['name']}", f"  {t['type'].upper()}"))
        self.status_var.set(f"Корень: {self.root_path if self.root_path else 'не задан'}")

    def get_selected_tool_names(self):
        selected_items = self.tree_run.selection()
        if not selected_items:
            return []
        return [self.tree_run.item(i, 'values')[0].strip() for i in selected_items]

    def run_selected_sequential(self):
        selected_names = self.get_selected_tool_names()
        if not selected_names:
            messagebox.showwarning("Внимание", "Выберите хотя бы один инструмент для запуска.")
            return
            
        for name in selected_names:
            tool = next((t for t in self.tools if t['name'] == name), None)
            if not tool:
                continue
                
            self.status_var.set(f"Запуск: {tool['name']}...")
            self.update()
            
            if tool['type'] == 'console':
                result = self.console_dialog(tool)
                if result is None:
                    continue
                if result == 'INTERACTIVE':
                    exe_path = resolve_path(tool['path'], self.root_path).strip('"')
                    if os.path.exists(exe_path):
                        subprocess.Popen(
                            f'start "Tool_{tool["name"]}" cmd /k "cd /d ""{os.path.dirname(exe_path)}"" && ""{exe_path}""',
                            shell=True,
                            creationflags=subprocess.CREATE_NEW_CONSOLE
                        )
                        write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                                  tool['name'], '0', 'Started (interactive)')
                    else:
                        write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                                  tool['name'], 'FILE_NOT_FOUND', '')
                        messagebox.showerror("Ошибка", f"Файл не найден:\n{exe_path}")
            else:
                exe_path = resolve_path(tool['path'], self.root_path).strip('"')
                if not os.path.exists(exe_path):
                    write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                              tool['name'], 'FILE_NOT_FOUND', '')
                    messagebox.showerror("Ошибка", f"Файл не найден:\n{exe_path}")
                    continue
                    
                stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + f'_{random.randint(1000,9999)}'
                log_path = os.path.join(LOG_DIR, f"{tool['name']}_{stamp}.log")
                os.makedirs(LOG_DIR, exist_ok=True)
                try:
                    with open(log_path, 'w', encoding='utf-8') as log_f:
                        proc = subprocess.Popen([exe_path], stdout=log_f, stderr=subprocess.STDOUT,
                                                creationflags=subprocess.CREATE_NO_WINDOW)
                        proc.wait()
                    exit_code = str(proc.returncode)
                except Exception as e:
                    exit_code = 'ERROR'
                    with open(log_path, 'w', encoding='utf-8') as log_f:
                        log_f.write(str(e))
                        
                if os.path.exists(log_path) and os.path.getsize(log_path) == 0:
                    os.remove(log_path)
                    log_path = ''
                    
                write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                          tool['name'], exit_code, log_path)
                          
        self.status_var.set("Готово")

    def run_selected_parallel(self):
        selected_names = self.get_selected_tool_names()
        if not selected_names:
            messagebox.showwarning("Внимание", "Выберите хотя бы один инструмент для запуска.")
            return
            
        for name in selected_names:
            self.status_var.set(f"Параллельный запуск: {name}...")
            self.update()
            
            if getattr(sys, 'frozen', False):
                cmd = [sys.executable, '__worker__', name]
            else:
                cmd = [sys.executable, os.path.abspath(__file__), '__worker__', name]
                
            subprocess.Popen(cmd, creationflags=subprocess.CREATE_NO_WINDOW)
            
        self.status_var.set("Инструменты запущены в фоне.")

    def console_dialog(self, tool):
        dialog = tk.Toplevel(self)
        dialog.title(f"Настройки: {tool['name']}")
        dialog.geometry("450x180")
        dialog.configure(bg=COLORS['bg'])
        dialog.transient(self)
        dialog.grab_set()
        dialog.update_idletasks()
        
        w, h = dialog.winfo_width(), dialog.winfo_height()
        x = (dialog.winfo_screenwidth() // 2) - (w // 2)
        y = (dialog.winfo_screenheight() // 2) - (h // 2)
        dialog.geometry(f'+{x}+{y}')
        
        result = []

        ttk.Label(dialog, text="Режим консольного запуска:", font=FONT_BOLD).pack(pady=(20, 10))

        btn_frame = ttk.Frame(dialog)
        btn_frame.pack(pady=10)
        
        ttk.Button(btn_frame, text="Интерактивно (cmd)", 
                   command=lambda: (result.append('INTERACTIVE'), dialog.destroy())).pack(side='left', padx=10)
        ttk.Button(btn_frame, text="С параметрами (фоном)", 
                   command=lambda: self.show_args_entry(dialog, tool, result)).pack(side='left', padx=10)

        self.wait_window(dialog)
        return result[0] if result else None

    def show_args_entry(self, parent, tool, result):
        parent.withdraw()
        d = tk.Toplevel(self)
        d.title(f"Аргументы: {tool['name']}")
        d.geometry("500x150")
        d.configure(bg=COLORS['bg'])
        d.transient(self)
        d.grab_set()
        
        d.update_idletasks()
        w, h = d.winfo_width(), d.winfo_height()
        x = (d.winfo_screenwidth() // 2) - (w // 2)
        y = (d.winfo_screenheight() // 2) - (h // 2)
        d.geometry(f'+{x}+{y}')
        
        ttk.Label(d, text="Введите аргументы (через пробел):").pack(pady=(15, 5))
        args_var = tk.StringVar()
        entry = ttk.Entry(d, textvariable=args_var, width=60)
        entry.pack(padx=20, pady=5)
        entry.focus()

        def on_ok():
            args = args_var.get().strip()
            exe_path = resolve_path(tool['path'], self.root_path).strip('"')
            if not os.path.exists(exe_path):
                messagebox.showerror("Ошибка", f"Файл не найден:\n{exe_path}", parent=d)
                d.destroy()
                result.append(None)
                return
                
            stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + f'_{random.randint(1000,9999)}'
            log_path = os.path.join(LOG_DIR, f"{tool['name']}_{stamp}.log")
            os.makedirs(LOG_DIR, exist_ok=True)
            
            try:
                cmd = [exe_path] + args.split()
                with open(log_path, 'w', encoding='utf-8') as log_f:
                    proc = subprocess.Popen(cmd, stdout=log_f, stderr=subprocess.STDOUT,
                                            cwd=os.path.dirname(exe_path),
                                            creationflags=subprocess.CREATE_NO_WINDOW)
                    proc.wait()
                exit_code = str(proc.returncode)
            except Exception as e:
                exit_code = 'ERROR'
                with open(log_path, 'w', encoding='utf-8') as log_f:
                    log_f.write(str(e))
                    
            write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                      tool['name'], exit_code, log_path)
            result.append('ARGS_DONE')
            d.destroy()
            parent.destroy()

        ttk.Button(d, text="Запустить", command=on_ok).pack(pady=10)
        self.wait_window(d)
        parent.destroy()

    def build_editor_tab(self):
        main_frame = ttk.Frame(self.tab_editor)
        main_frame.pack(fill='both', expand=True, padx=20, pady=20)

        path_frame = ttk.LabelFrame(main_frame, text="Базовая директория (корень)")
        path_frame.pack(fill='x', pady=(0, 15))
        self.root_var = tk.StringVar(value=self.root_path or "")
        
        path_inner = ttk.Frame(path_frame)
        path_inner.pack(fill='x', padx=10, pady=10)
        
        ttk.Entry(path_inner, textvariable=self.root_var).pack(side='left', padx=(0, 10), expand=True, fill='x')
        ttk.Button(path_inner, text="💾 Сохранить путь", command=self.save_root_path).pack(side='left')

        content_container = ttk.Frame(main_frame)
        content_container.pack(fill='both', expand=True)

        right_frame = ttk.LabelFrame(content_container, text="Детали инструмента")
        right_frame.pack(side='right', fill='y', padx=(20, 0)) 
        
        r_inner = ttk.Frame(right_frame)
        r_inner.pack(fill='both', expand=True, padx=15, pady=15)

        ttk.Label(r_inner, text="Название:").grid(row=0, column=0, sticky='w', pady=10)
        self.edit_name_var = tk.StringVar()
        ttk.Entry(r_inner, textvariable=self.edit_name_var, width=25).grid(row=0, column=1, sticky='ew', padx=(10, 0), pady=10)

        ttk.Label(r_inner, text="Тип:").grid(row=1, column=0, sticky='w', pady=10)
        self.edit_type_var = tk.StringVar(value='gui')
        ttk.Combobox(r_inner, textvariable=self.edit_type_var, values=['gui', 'console'], 
                     state='readonly', width=23).grid(row=1, column=1, sticky='w', padx=(10, 0), pady=10)

        ttk.Label(r_inner, text="Путь:").grid(row=2, column=0, sticky='w', pady=10)
        self.edit_path_var = tk.StringVar()
        ttk.Entry(r_inner, textvariable=self.edit_path_var, width=25).grid(row=2, column=1, sticky='ew', padx=(10, 0), pady=10)
        
        r_inner.columnconfigure(1, weight=1)

        left_frame = ttk.Frame(content_container)
        left_frame.pack(side='left', fill='both', expand=True)

        ttk.Label(left_frame, text="Список настроенных инструментов:", font=FONT_BOLD).pack(anchor='w', pady=(0, 5))
        
        tree_frame = ttk.Frame(left_frame)
        tree_frame.pack(fill='both', expand=True)
        
        self.tree_editor = ttk.Treeview(tree_frame, columns=('name', 'type', 'path'), show='headings')
        self.tree_editor.heading('name', text='Имя', anchor='w')
        self.tree_editor.heading('type', text='Тип', anchor='w')
        self.tree_editor.heading('path', text='Путь', anchor='w')
        
        self.tree_editor.column('name', width=150, anchor='w')
        self.tree_editor.column('type', width=80, anchor='w')
        self.tree_editor.column('path', width=250, anchor='w')
        
        self.tree_editor.pack(side='left', fill='both', expand=True)
        
        scroll_ed = ttk.Scrollbar(tree_frame, orient='vertical', command=self.tree_editor.yview)
        scroll_ed.pack(side='right', fill='y')
        self.tree_editor.configure(yscrollcommand=scroll_ed.set)
        self.tree_editor.bind('<<TreeviewSelect>>', self.on_editor_select)

        btn_frame = ttk.Frame(left_frame)
        btn_frame.pack(fill='x', pady=10)
        ttk.Button(btn_frame, text="➕ Добавить", command=self.add_tool).pack(side='left', padx=(0, 5))
        ttk.Button(btn_frame, text="✏️ Изменить", command=self.edit_tool).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="🗑️ Удалить", command=self.delete_tool).pack(side='left', padx=5)

    def refresh_editor_list(self):
        self.tools = load_tools()
        for item in self.tree_editor.get_children():
            self.tree_editor.delete(item)
        for t in self.tools:
            self.tree_editor.insert('', 'end', values=(t['name'], t['type'], t['path']))

    def on_editor_select(self, event):
        sel = self.tree_editor.selection()
        if not sel:
            return
        item = self.tree_editor.item(sel[0])
        values = item['values']
        self.edit_name_var.set(values[0])
        self.edit_type_var.set(values[1])
        self.edit_path_var.set(values[2])

    def save_root_path(self):
        new_root = self.root_var.get().strip()
        save_root(new_root)
        self.root_path = new_root
        self.refresh_tools_list()
        self.status_var.set("Путь успешно обновлен.")

    def add_tool(self):
        name = self.edit_name_var.get().strip()
        ttype = self.edit_type_var.get()
        path = self.edit_path_var.get().strip()
        if not name or not path:
            messagebox.showerror("Ошибка", "Имя и путь не могут быть пустыми.")
            return
        if any(t['name'] == name for t in self.tools):
            messagebox.showerror("Ошибка", "Инструмент с таким именем уже существует.")
            return
        self.tools.append({'name': name, 'type': ttype, 'path': path})
        save_tools(self.tools)
        self.refresh_editor_list()
        self.refresh_tools_list()
        self.status_var.set("Инструмент добавлен.")

    def edit_tool(self):
        sel = self.tree_editor.selection()
        if not sel:
            messagebox.showwarning("Внимание", "Выберите инструмент из списка для изменения.")
            return
        idx = self.tree_editor.index(sel[0])
        new_name = self.edit_name_var.get().strip()
        new_type = self.edit_type_var.get()
        new_path = self.edit_path_var.get().strip()
        if not new_name or not new_path:
            messagebox.showerror("Ошибка", "Имя и путь не могут быть пустыми.")
            return
        if any(t['name'] == new_name for i, t in enumerate(self.tools) if i != idx):
            messagebox.showerror("Ошибка", "Инструмент с таким именем уже существует.")
            return
        self.tools[idx] = {'name': new_name, 'type': new_type, 'path': new_path}
        save_tools(self.tools)
        self.refresh_editor_list()
        self.refresh_tools_list()
        self.status_var.set("Инструмент обновлен.")

    def delete_tool(self):
        sel = self.tree_editor.selection()
        if not sel:
            messagebox.showwarning("Внимание", "Выберите инструмент для удаления.")
            return
        if messagebox.askyesno("Удаление", "Удалить выбранный инструмент?"):
            idx = self.tree_editor.index(sel[0])
            del self.tools[idx]
            save_tools(self.tools)
            self.refresh_editor_list()
            self.refresh_tools_list()
            self.status_var.set("Инструмент удален.")

    def build_report_tab(self):
        main_frame = ttk.Frame(self.tab_report)
        main_frame.pack(fill='both', expand=True, padx=20, pady=20)

        top_frame = ttk.Frame(main_frame)
        top_frame.pack(fill='x', pady=(0, 10))
        ttk.Button(top_frame, text="📄 Сгенерировать свежий отчёт", command=self.generate_report).pack(side='left')

        self.report_text = scrolledtext.ScrolledText(main_frame, wrap='word',
                                                     font=('Consolas', 10),
                                                     bg='#1E1E1E', fg='#D4D4D4',
                                                     padx=10, pady=10, borderwidth=0)
        self.report_text.pack(fill='both', expand=True)

    def generate_report(self):
        if not os.path.exists(LOG_FILE):
            self.report_text.delete('1.0', 'end')
            self.report_text.insert('1.0', "Лог-файл отсутствует. Выполните хотя бы один запуск.")
            return

        total = ok = fail = 0
        rows = []
        with open(LOG_FILE, 'r', encoding='utf-8') as f:
            reader = csv.reader(f, delimiter=';')
            header = next(reader, None)
            for row in reader:
                if len(row) >= 4:
                    total += 1
                    if row[3].strip().upper() in ['FILE_NOT_FOUND', 'ERROR']:
                        fail += 1
                    else:
                        ok += 1
                    rows.append(row)

        report_lines = []
        report_lines.append("=" * 70)
        report_lines.append(f" ОТЧЁТ О ЗАПУСКАХ ИНСТРУМЕНТОВ ".center(70, "="))
        report_lines.append("=" * 70)
        report_lines.append(f"Дата формирования : {datetime.datetime.now().strftime('%d.%m.%Y %H:%M:%S')}")
        report_lines.append(f"Всего запусков    : {total}")
        report_lines.append(f"Успешных          : {ok}")
        report_lines.append(f"С ошибками        : {fail}")
        report_lines.append("-" * 70)
        report_lines.append(f"{'Дата':<12} | {'Время':<10} | {'Инструмент':<20} | {'Код':<6} | {'Лог'}")
        report_lines.append("-" * 70)
        
        for r in rows:
            log_name = os.path.basename(r[4]) if len(r) > 4 and r[4] else "Нет"
            report_lines.append(f"{r[0]:<12} | {r[1]:<10} | {r[2][:19]:<20} | {r[3][:6]:<6} | {log_name}")
            
        report_lines.append("=" * 70)
        report_lines.append("\n[ ЛОГИ ВЫВОДА ОШИБОК И РЕЗУЛЬТАТОВ ]\n")
        
        for r in rows:
            if len(r) > 4 and r[4] and os.path.exists(r[4]):
                report_lines.append(f"► Инструмент: {r[2]} (Код возврата: {r[3]})")
                report_lines.append("-" * 40)
                with open(r[4], 'r', encoding='utf-8', errors='replace') as lf:
                    content = lf.read().strip()
                    report_lines.append(content if content else "<Пустой вывод>")
                report_lines.append("-" * 40 + "\n")

        report_str = '\n'.join(report_lines)
        with open(REPORT_FILE, 'w', encoding='utf-8') as rf:
            rf.write(report_str)

        self.report_text.delete('1.0', 'end')
        self.report_text.insert('1.0', report_str)
        self.status_var.set("Отчёт сгенерирован")

if __name__ == '__main__':
    os.makedirs(REPORT_DIR, exist_ok=True)
    os.makedirs(LOG_DIR, exist_ok=True)
    
    if not os.path.exists(CONFIG_FILE):
        open(CONFIG_FILE, 'w', encoding='utf-8').close()
    if not os.path.exists(ROOT_FILE):
        open(ROOT_FILE, 'w', encoding='utf-8').close()

    if len(sys.argv) > 1 and sys.argv[1] == '__worker__':
        tool_name = sys.argv[2] if len(sys.argv) > 2 else None
        if tool_name:
            worker_process(tool_name)
        sys.exit(0)
    else:
        app = App()
        app.mainloop()