export interface Gunk {
  id: number;
  name: string;
  path: string;
  droppedAt: number;
  removedAt: number | null;
}

export interface GunkFile {
  id: number;
  gunkId: number;
  relpath: string;
  size: number | null;
}
