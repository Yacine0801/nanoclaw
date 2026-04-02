"""
## Documentation
Quickstart: https://github.com/google-gemini/cookbook/blob/main/quickstarts/Get_started_LiveAPI.py

## Setup

To install the dependencies for this script, run:

```
pip install google-genai opencv-python pyaudio pillow mss
```
"""

import os
import sys
import asyncio
import base64
import io
import traceback

import cv2
import pyaudio
import PIL.Image

import argparse
import pathlib

from google import genai
from google.genai import types
from google.genai.types import Type

FORMAT = pyaudio.paInt16
CHANNELS = 1
SEND_SAMPLE_RATE = 16000
RECEIVE_SAMPLE_RATE = 24000
CHUNK_SIZE = 1024

MODEL = os.environ.get("GEMINI_MODEL", "models/gemini-2.5-flash-native-audio-latest")

DEFAULT_MODE = "camera"

# NanoClaw memory paths (local dev)
MEMORY_PATHS = {
    "botti": os.environ.get("NANOCLAW_BOTTI_MEMORY",
        str(pathlib.Path(__file__).parent / "groups" / "whatsapp_main" / "CLAUDE.md")),
    "sam": os.environ.get("NANOCLAW_SAM_MEMORY",
        str(pathlib.Path(__file__).parent / "groups" / "global" / "CLAUDE.md")),
    "thais": os.environ.get("NANOCLAW_THAIS_MEMORY",
        str(pathlib.Path(__file__).parent.parent / "nanoclaw-thais" / "groups" / "gmail_main" / "CLAUDE.md")),
}

VOICE_PREAMBLE = """Tu es en mode vocal.
- Tutoie toujours Yacine. Jamais de vouvoiement.
- Français par défaut. Anglais si Yacine parle anglais ou si le contexte l'exige.
- Factuel, direct, dense. Zéro flatterie, zéro "bien sûr", zéro "excellente question".
- Réponses courtes : 3-4 phrases max sauf demande explicite de développement.
- Quand tu listes, 3 items max. Si il y en a plus, demande si tu continues.
- Pas de markdown en vocal — tu parles, tu ne rédiges pas."""


def load_agent_memory(agent_name: str) -> str:
    """Load CLAUDE.md for the given agent, fall back to built-in prompt."""
    path = MEMORY_PATHS.get(agent_name)
    if path:
        try:
            return VOICE_PREAMBLE + "\n\n" + pathlib.Path(path).read_text()
        except FileNotFoundError:
            print(f"[warn] Memory not found for {agent_name}: {path}")
    return VOICE_PREAMBLE


client = genai.Client(
    http_options={"api_version": "v1beta"},
    api_key=os.environ.get("GEMINI_API_KEY"),
)

tools = [
    types.Tool(google_search=types.GoogleSearch()),
    types.Tool(
        function_declarations=[
        ]
    ),
]

def build_config(agent_name: str = "botti") -> types.LiveConnectConfig:
    """Build Gemini Live config with memory from NanoClaw agent."""
    prompt = load_agent_memory(agent_name)
    print(f"[info] Loaded {agent_name} memory ({len(prompt)} chars)")
    return types.LiveConnectConfig(
        response_modalities=["AUDIO"],
        media_resolution="MEDIA_RESOLUTION_MEDIUM",
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name="Kore")
            )
        ),
        context_window_compression=types.ContextWindowCompressionConfig(
            trigger_tokens=104857,
            sliding_window=types.SlidingWindow(target_tokens=52428),
        ),
        tools=tools,
        system_instruction=types.Content(
            parts=[types.Part.from_text(text=prompt)],
            role="user",
        ),
    )

pya = pyaudio.PyAudio()


def list_audio_devices():
    """Print all available audio devices and exit."""
    print("\nAvailable audio devices:\n")
    for i in range(pya.get_device_count()):
        info = pya.get_device_info_by_index(i)
        direction = []
        if info["maxInputChannels"] > 0:
            direction.append("IN")
        if info["maxOutputChannels"] > 0:
            direction.append("OUT")
        print(f"  [{i}] {info['name']}  ({'/'.join(direction)})")
    print()


class AudioLoop:
    def __init__(self, video_mode=DEFAULT_MODE, input_device=None, output_device=None, agent_name="botti"):
        self.video_mode = video_mode
        self.input_device = input_device
        self.output_device = output_device
        self.agent_name = agent_name

        self.audio_in_queue = None
        self.out_queue = None

        self.session = None

        self.send_text_task = None
        self.receive_audio_task = None
        self.play_audio_task = None

        self.audio_stream = None

        # Full-duplex: mic always on, Gemini server-side VAD handles turn-taking

    async def send_text(self):
        while True:
            text = await asyncio.to_thread(
                input,
                "message > ",
            )
            if text.lower() == "q":
                break
            if self.session is not None:
                await self.session.send(input=text or ".", end_of_turn=True)

    def _get_frame(self, cap):
        ret, frame = cap.read()
        if not ret:
            return None
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        img = PIL.Image.fromarray(frame_rgb)
        img.thumbnail([1024, 1024])

        image_io = io.BytesIO()
        img.save(image_io, format="jpeg")
        image_io.seek(0)

        mime_type = "image/jpeg"
        image_bytes = image_io.read()
        return {"mime_type": mime_type, "data": base64.b64encode(image_bytes).decode()}

    async def get_frames(self):
        cap = await asyncio.to_thread(
            cv2.VideoCapture, 0
        )

        while True:
            frame = await asyncio.to_thread(self._get_frame, cap)
            if frame is None:
                break

            await asyncio.sleep(1.0)

            if self.out_queue is not None:
                await self.out_queue.put(frame)

        cap.release()

    def _get_screen(self):
        try:
            import mss
        except ImportError as e:
            raise ImportError("Please install mss package using 'pip install mss'") from e
        sct = mss.mss()
        monitor = sct.monitors[0]

        i = sct.grab(monitor)

        mime_type = "image/jpeg"
        image_bytes = mss.tools.to_png(i.rgb, i.size)
        img = PIL.Image.open(io.BytesIO(image_bytes))

        image_io = io.BytesIO()
        img.save(image_io, format="jpeg")
        image_io.seek(0)

        image_bytes = image_io.read()
        return {"mime_type": mime_type, "data": base64.b64encode(image_bytes).decode()}

    async def get_screen(self):

        while True:
            frame = await asyncio.to_thread(self._get_screen)
            if frame is None:
                break

            await asyncio.sleep(1.0)

            if self.out_queue is not None:
                await self.out_queue.put(frame)

    async def send_realtime(self):
        while True:
            if self.out_queue is not None:
                msg = await self.out_queue.get()
                if self.session is not None:
                    await self.session.send(input=msg)

    async def listen_audio(self):
        if self.input_device is not None:
            device_index = self.input_device
        else:
            mic_info = pya.get_default_input_device_info()
            device_index = mic_info["index"]

        self.audio_stream = await asyncio.to_thread(
            pya.open,
            format=FORMAT,
            channels=CHANNELS,
            rate=SEND_SAMPLE_RATE,
            input=True,
            input_device_index=device_index,
            frames_per_buffer=CHUNK_SIZE,
        )
        if __debug__:
            kwargs = {"exception_on_overflow": False}
        else:
            kwargs = {}
        while True:
            data = await asyncio.to_thread(self.audio_stream.read, CHUNK_SIZE, **kwargs)
            if self.out_queue is not None:
                await self.out_queue.put({"data": data, "mime_type": "audio/pcm"})

    async def receive_audio(self):
        "Background task to reads from the websocket and write pcm chunks to the output queue"
        while True:
            if self.session is not None:
                turn = self.session.receive()
                async for response in turn:
                    if data := response.data:
                        self.audio_in_queue.put_nowait(data)
                        continue
                    if text := response.text:
                        print(text, end="")

                # If you interrupt the model, it sends a turn_complete.
                # For interruptions to work, we need to stop playback.
                # So empty out the audio queue because it may have loaded
                # much more audio than has played yet.
                while not self.audio_in_queue.empty():
                    self.audio_in_queue.get_nowait()

    async def play_audio(self):
        output_kwargs = {}
        if self.output_device is not None:
            output_kwargs["output_device_index"] = self.output_device

        stream = await asyncio.to_thread(
            pya.open,
            format=FORMAT,
            channels=CHANNELS,
            rate=RECEIVE_SAMPLE_RATE,
            output=True,
            **output_kwargs,
        )
        while True:
            if self.audio_in_queue is not None:
                bytestream = await self.audio_in_queue.get()
                await asyncio.to_thread(stream.write, bytestream)

    async def run(self):
        try:
            async with (
                client.aio.live.connect(model=MODEL, config=build_config(self.agent_name)) as session,
                asyncio.TaskGroup() as tg,
            ):
                self.session = session

                self.audio_in_queue = asyncio.Queue()
                self.out_queue = asyncio.Queue(maxsize=5)

                send_text_task = tg.create_task(self.send_text())
                tg.create_task(self.send_realtime())
                tg.create_task(self.listen_audio())
                if self.video_mode == "camera":
                    tg.create_task(self.get_frames())
                elif self.video_mode == "screen":
                    tg.create_task(self.get_screen())

                tg.create_task(self.receive_audio())
                tg.create_task(self.play_audio())

                await send_text_task
                raise asyncio.CancelledError("User requested exit")

        except asyncio.CancelledError:
            pass
        except ExceptionGroup as EG:
            if self.audio_stream is not None:
                self.audio_stream.close()
                traceback.print_exception(EG)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode",
        type=str,
        default=DEFAULT_MODE,
        help="pixels to stream from",
        choices=["camera", "screen", "none"],
    )
    parser.add_argument(
        "--input-device",
        type=int,
        default=None,
        help="PyAudio input device index (use --list-devices to see)",
    )
    parser.add_argument(
        "--output-device",
        type=int,
        default=None,
        help="PyAudio output device index (use --list-devices to see)",
    )
    parser.add_argument(
        "--list-devices",
        action="store_true",
        help="List available audio devices and exit",
    )
    parser.add_argument(
        "--agent",
        type=str,
        default="botti",
        choices=["botti", "sam", "thais"],
        help="Which agent personality to load (default: botti)",
    )
    args = parser.parse_args()

    if args.list_devices:
        list_audio_devices()
        sys.exit(0)

    main = AudioLoop(
        video_mode=args.mode,
        input_device=args.input_device,
        output_device=args.output_device,
        agent_name=args.agent,
    )
    asyncio.run(main.run())
