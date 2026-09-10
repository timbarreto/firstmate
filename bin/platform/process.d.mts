// Compatibility declarations for the shared process implementation.
export function isPidInCurrentAncestry(pid: string, maxDepth?: number): boolean;
export function shellVisibleProcessPid(): number;
export function pidAlive(pid: string): boolean;
export function signalWatchArmProcess(pid: number | undefined, ownerToken?: string): boolean;
export function terminateWatchArmProcessTree(pid: number | undefined, ownerToken?: string): boolean;
