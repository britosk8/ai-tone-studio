"""JSON progress emitted after Demucs consumes each completed inference chunk."""

import json


def emit(stage, **fields):
    print(json.dumps({"event": "progress", "stage": stage, **fields}), flush=True)


class ChunkProgress:
    def __init__(self, model_count=1):
        self.model_count = model_count
        self.completed = 0
        self.total = None

    def __call__(self, items, **kwargs):
        # Demucs applies every ensemble member with identical segment/overlap.
        total = len(items) * self.model_count
        if self.total is None:
            self.total = total
        elif self.total != total:
            raise ValueError("Demucs retornou contagem de blocos inconsistente")
        emit("separating", completed=self.completed, total=self.total)
        for item in items:
            yield item
            # The consumer has awaited future.result() and mixed the chunk.
            self.completed += 1
            emit("separating", completed=self.completed, total=self.total)
