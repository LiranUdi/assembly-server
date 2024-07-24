# compile with debugging symbols
compile:
	as --gstabs -o server.o server.asm
	ld -o server server.o

run:
	./server

trace:
	strace ./server

clean:
	rm -f server.o server
