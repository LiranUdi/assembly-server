# TODO: Debug issue with malformed request 
# Making a request with "HTTP SOMEFILE" will write "SOMEFILE" to the current directory the server was launched from

.intel_syntax noprefix
.globl _start

# constants
.set SYS_READ, 0
.set SYS_WRITE, 1
.set SYS_OPEN, 2
.set SYS_CLOSE, 3
.set SYS_SOCKET, 41
.set SYS_ACCEPT, 43
.set SYS_BIND, 49
.set SYS_LISTEN, 50
.set SYS_EXIT, 60
.set SYS_FORK, 57

# constant args
.set AF_INET, 2
.set SOCK_STREAM, 1
.set IPPROTO_IP, 0
.set ADDRLEN_16, 16

# for file usage
.set O_RDONLY, 0
.set O_WRONLY, 1
.set O_CREAT, 0x40
.set BUFFERSIZE, 8192   

# [V] execve(<execve_args>) = 0                                                                                 

# Handle multiple GET and POST requests                       #
# A loop will recieve incoming connections and sort them by   #
# GET and POST requests and into an separate child process for#
# concurrency                                                 #



# the program is expecting a socket
# socket(AF_INET, SOCK_STREAM, IPPROTO_IP)
_start:
    endbr64
    push rbp
    mov rbp, rsp

    # create the socket!
    # [V] socket(AF_INET, SOCK_STREAM, IPPROTO_IP) = 3   
    mov rdi, AF_INET # ARG0, AF_INET
    mov rsi, SOCK_STREAM # ARG1, SOCK_STREAM
    mov rdx, IPPROTO_IP # ARG2, IPPROTO_IP                                                         
    call socket

    mov r12, rax 


    # [V] bind(3, {sa_family=AF_INET, sin_port=htons(<bind_port>), sin_addr=inet_addr("<bind_address>")}, 16) = 0   
    #    - Bind to port 80                                                                                         
    #    - Bind to address 0.0.0.0 
        # size of the struct, reserve some space
    sub rsp, ADDRLEN_16 # clear some space on the stack

    mov word ptr [rbp-16], AF_INET      # sa_family AF _INET
    mov word ptr [rbp-14], 0x5000 # sin_port Port 80
    mov dword ptr [rbp-12], 0      # sin_addr IP 0.0.0.0
    mov qword ptr [rbp-8], 0      # padding, 0
    

    mov rdi, r12            # FD
    mov rsi, rsp            # THE addr struct
    mov rdx, ADDRLEN_16     # addrlen
    call bind
    add rsp, ADDRLEN_16


    # listen on the socket
    # [V] listen(3, 0) = 0 
    mov rdi, r12 # Socket FD
    mov rsi, 5   # backlog
    call listen


    # [V] exit(0) = ?
    jmp loop



loop:
    endbr64
    sub rsp, 8 # clear some space on the stack

    mov rdi, r12 # get the socket's FD
    xor rsi, rsi
    xor rdx, rdx
    call accept # accept the incoming request

    mov [rbp-8], rax # save the result from accept

    mov rax, SYS_FORK
    syscall

    cmp rax, 0
    je child_process

    mov rdi, [rbp-8] # close the connection
    call close

    jmp loop # keep looping

# create a child process
# fork(void)
child_process:
    endbr64

    mov rdi, r12
    call close

    # call read - Get the request
    # [V] read(4, <read_request>, <read_request_count>) = <read_request_result>  
    sub rsp, BUFFERSIZE   # clear up some space on the stack for the request

    mov rdi, [rbp-8]            # FD of the connection accepted previously
    mov rsi, rsp          # buffer address to read the request
    mov rdx, BUFFERSIZE   # size of the buffer
    call read

    mov r12, rax # Save of the size of the actual buffer without the nulls

    mov r10, rsp # Get the contents from the stack into r10
    cmp byte ptr [r10+3], 0x20
    je handle_GET


    # POST REQUEST
    add r10, 5                # skip the POST part of the request
    mov byte ptr [r10+16], 0  # get only the filename, add a null byte

    mov rdi, r10               # set the filename
    mov rsi, O_WRONLY          # set to create if the file doesn't exist
    or rsi, O_CREAT            # set to write only
    mov rdx, 0777              # set the flag to 0777 (RWX)
    call open
    push rax    # push the result of RAX
    push rax


    sub r10, 5 

    mov byte ptr [r10+16], 0x20


    # get the request's size dynamically
    mov rdi, r10              # contents
    mov rsi, r12
    call find_offset
    mov rbx, rax

    pop rdi # FD pushed earlier from OPEN
    mov rsi, r10        # contents to write *buf
    add rsi, rbx
    sub r12, rbx
    mov rdx, r12
    call write


    # [V] close(5) = 0             
    pop rdi # Get the value stored from RAX, the file's FD
    call close


    # [V] write(4, "HTTP/1.0 200 OK\r\n\r\n", 19) = 19
    # respond to a connection with a header
    mov rdi, [rbp-8]        # FD of the connection
    lea rsi, response   # the response ascii
    mov rdx, 19         # size of the response
    call write

    # [V] Child Process: Missing `exit(0) = ?`
    xor rdi, rdi
    call exit   
    

# find the offset
find_offset:
    endbr64

    push rbp
    mov rbp, rsp

    sub rsp, 8

    mov qword ptr [rbp-8], 0

    # seek to the end
    add rdi, rsi

    jmp check_offset

check_offset:
    # 0xd = "\r"
    cmp byte ptr [rdi], 0xd
    je found_offset
    dec rdi

    mov rbx, [rbp-0x8]
    inc rbx
    mov [rbp-0x8], rbx

    jmp check_offset

found_offset:
    mov rax, [rbp-0x8]
    sub rsi, rax
    mov rax, rsi
    add rax, 2

    add rsp, 8

    leave
    ret 

handle_GET:
    endbr64

    add r10, 4 # SKIP the GET
    mov qword ptr [r10+16], 0 # get only the filename


    # Read the file to respond with
    mov rdi, r10      # set the filename
    mov rsi, O_RDONLY              # set to read only
    call open


    push rax # FD


    # [V] read(5, <read_file>, <read_file_count>) = <read_file_result>                           
    # read the contents of the file
    pop rdi
    push rdi
    mov rsi, r10
    mov rdx, BUFFERSIZE
    call read

    push rax # Size

    mov r13, rax # push the size of the actual contents in the file

    # [V] close(5) = 0                               
    call close


    # [V] write(4, "HTTP/1.0 200 OK\r\n\r\n", 19) = 19
    mov rdi, [rbp-8]        # FD of the connection
    # respond to a connection with a header
    lea rsi, response   # the response ascii
    mov rdx, 19         # size of the response
    call write

 
    # [V] write(4, <write_file>, <write_file_count> = <write_file_result>
    # response body
    mov rdi, [rbp-8]        # FD of the connection
    mov rsi, r10        # contents of the file saved on the stack (mov r10, rsp)
    pop rdx             # size of the file, get the actual size saved on the stack
    call write

    mov rdi, [rbp-8]
    call close

    xor rdi, rdi
    call exit   




# socket(int domain, int type, int protocol)
socket:
    endbr64
    push rbp
    mov rbp, rsp

    # create a socket(AF_INET, SOCK_STREAM, IPPROTO_IP)
    mov rax, SYS_SOCKET # sys_socket
    syscall

    leave
    ret

# bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen)
bind:
    endbr64
    # save rbp
    push rbp
    mov rbp, rsp

    # bind socket
    mov rax, SYS_BIND #sys_bind
    syscall


    leave
    ret # equ mov rsp, rbp, pop rbp

# listen(int sockfd, int backlog)
listen:
    endbr64
    push rbp
    mov rbp, rsp

    # start listening
    mov rax, SYS_LISTEN
    syscall 

    leave
    ret

# accept(int sockfd, struct sockaddr *restrict addr, socklen_t *restrict addrlen)
accept:
    endbr64
    push rbp
    mov rbp, rsp

    mov rax, SYS_ACCEPT
    syscall


    leave
    ret



# open(const char *pathname, int flags, mode_t mode)
open:
    endbr64
    push rbp
    mov rbp, rsp

    mov rax, SYS_OPEN
    syscall

    leave
    ret

# read(int fd, void *buf, size_t count)
read:
    endbr64
    push rbp
    mov rbp, rsp
     
    mov rax, SYS_READ
    syscall

    leave
    ret

# write(int fd, const void *buf, size_t count)
write:
    endbr64
    push rbp
    mov rbp, rsp

    mov rax, SYS_WRITE
    syscall

    leave
    ret


# close(int fd)
close:
    endbr64
    push rbp
    mov rbp, rsp

    # set rdi to the FD of the connection I accepted earlier
    # mov rdi, rax
    mov rax, SYS_CLOSE
    syscall

    leave
    ret

# exit(int code)
exit:
    endbr64
    push rbp
    mov rsp, rbp

    mov rdi, 0
    mov rax, SYS_EXIT
    syscall

    leave
    ret

response:
    .ascii "HTTP/1.0 200 OK\r\n\r\n"

test_file:
    .ascii "/var/www/assembly-server/index.html"

.section .data
    .lcomm buffer, 1024
    .lcomm file_buff, 1024
    .lcomm filename, 15

